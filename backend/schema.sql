create schema if not exists private;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  phone text check (phone is null or char_length(phone) <= 24),
  created_at timestamptz not null default now()
);

create table public.circles (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  owner_id uuid not null references auth.users(id) on delete cascade,
  invite_code text not null unique,
  created_at timestamptz not null default now()
);
create index circles_owner_idx on public.circles(owner_id);

create table public.circle_members (
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (circle_id, user_id)
);
create index circle_members_user_idx on public.circle_members(user_id);

create table public.alerts (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind text not null check (kind in ('sos','missed_checkin','checkin_started','walk','location','safe')),
  message text check (message is null or char_length(message) <= 500),
  lat double precision, lng double precision, accuracy integer, battery integer,
  status text not null default 'active' check (status in ('active','resolved')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index alerts_sender_idx on public.alerts(sender_id, created_at desc);

create table public.alert_responses (
  alert_id uuid not null references public.alerts(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  response text not null check (response in ('seen','on_my_way','calling','called_police')),
  created_at timestamptz not null default now(),
  primary key (alert_id, user_id)
);
create index alert_responses_user_idx on public.alert_responses(user_id);

create table public.live_locations (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  lat double precision not null, lng double precision not null,
  accuracy integer, battery integer,
  note text check (note is null or char_length(note) <= 140),
  sharing_until timestamptz not null,
  updated_at timestamptz not null default now()
);

create table public.push_subscriptions (
  endpoint text primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);
create index push_subscriptions_user_idx on public.push_subscriptions(user_id);

create table private.app_secrets (name text primary key, value text not null);

-- helpers (private schema is not exposed through the API)
create or replace function private.shares_circle(other uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.circle_members a
    join public.circle_members b on a.circle_id = b.circle_id
    where a.user_id = (select auth.uid()) and b.user_id = other
  );
$$;
create or replace function private.is_member(c uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.circle_members where circle_id = c and user_id = (select auth.uid()));
$$;
grant usage on schema private to authenticated;
grant execute on function private.shares_circle(uuid), private.is_member(uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.circles enable row level security;
alter table public.circle_members enable row level security;
alter table public.alerts enable row level security;
alter table public.alert_responses enable row level security;
alter table public.live_locations enable row level security;
alter table public.push_subscriptions enable row level security;

create policy "see own and circle profiles" on public.profiles for select to authenticated
  using (id = (select auth.uid()) or private.shares_circle(id));
create policy "create own profile" on public.profiles for insert to authenticated
  with check (id = (select auth.uid()));
create policy "update own profile" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "members see circle" on public.circles for select to authenticated
  using (private.is_member(id));
create policy "owner deletes circle" on public.circles for delete to authenticated
  using (owner_id = (select auth.uid()));

create policy "members see members" on public.circle_members for select to authenticated
  using (private.is_member(circle_id));
create policy "leave or remove" on public.circle_members for delete to authenticated
  using (user_id = (select auth.uid()) or exists (select 1 from public.circles c where c.id = circle_id and c.owner_id = (select auth.uid())));

create policy "send own alerts" on public.alerts for insert to authenticated
  with check (sender_id = (select auth.uid()));
create policy "see own and circle alerts" on public.alerts for select to authenticated
  using (sender_id = (select auth.uid()) or private.shares_circle(sender_id));
create policy "resolve own alerts" on public.alerts for update to authenticated
  using (sender_id = (select auth.uid())) with check (sender_id = (select auth.uid()));

create policy "see responses to visible alerts" on public.alert_responses for select to authenticated
  using (exists (select 1 from public.alerts a where a.id = alert_id));
create policy "respond to circle alerts" on public.alert_responses for insert to authenticated
  with check (user_id = (select auth.uid()) and exists (select 1 from public.alerts a where a.id = alert_id and a.sender_id <> (select auth.uid())));
create policy "change own response" on public.alert_responses for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "see own and active circle locations" on public.live_locations for select to authenticated
  using (user_id = (select auth.uid()) or (sharing_until > now() and private.shares_circle(user_id)));
create policy "share own location" on public.live_locations for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "update own location" on public.live_locations for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "stop own location" on public.live_locations for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "own push subscriptions" on public.push_subscriptions for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- circles: created and joined only through these functions
create or replace function public.create_circle(p_name text) returns public.circles
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  code text;
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  c public.circles;
begin
  if me is null then raise exception 'not signed in'; end if;
  if (select count(*) from public.circles where owner_id = me) >= 10 then raise exception 'You can create up to 10 circles'; end if;
  loop
    code := '';
    for i in 1..8 loop code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
    exit when not exists (select 1 from public.circles where invite_code = code);
  end loop;
  insert into public.circles(name, owner_id, invite_code) values (trim(p_name), me, code) returning * into c;
  insert into public.circle_members(circle_id, user_id) values (c.id, me);
  return c;
end $$;

create or replace function public.join_circle(p_code text) returns public.circles
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  c public.circles;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into c from public.circles where invite_code = upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g'));
  if c.id is null then raise exception 'That invite code was not found'; end if;
  if (select count(*) from public.circle_members where circle_id = c.id) >= 25 then raise exception 'This circle is full (25 people)'; end if;
  insert into public.circle_members(circle_id, user_id) values (c.id, me) on conflict do nothing;
  return c;
end $$;

create or replace function public.new_invite_code(p_circle uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare code text; alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  if not exists (select 1 from public.circles where id = p_circle and owner_id = auth.uid()) then raise exception 'Only the circle owner can do this'; end if;
  loop
    code := '';
    for i in 1..8 loop code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
    exit when not exists (select 1 from public.circles where invite_code = code);
  end loop;
  update public.circles set invite_code = code where id = p_circle;
  return code;
end $$;

create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  delete from auth.users where id = auth.uid();
end $$;

-- service role only: lets the push function read its signing key
create or replace function public.get_app_secret(p_name text) returns text
language sql stable security definer set search_path = '' as $$
  select value from private.app_secrets where name = p_name;
$$;

revoke all on function public.create_circle(text), public.join_circle(text), public.new_invite_code(uuid), public.delete_my_account(), public.get_app_secret(text) from public, anon;
grant execute on function public.create_circle(text), public.join_circle(text), public.new_invite_code(uuid), public.delete_my_account() to authenticated;
revoke execute on function public.get_app_secret(text) from authenticated;
grant execute on function public.get_app_secret(text) to service_role;

-- keep history short: alerts older than 30 days are removed when the sender sends a new one
create or replace function private.trim_old_alerts() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.alerts where sender_id = new.sender_id and created_at < now() - interval '30 days';
  return new;
end $$;
create trigger alerts_trim after insert on public.alerts for each row execute function private.trim_old_alerts();

alter publication supabase_realtime add table public.alerts, public.alert_responses, public.live_locations;
-- additions before first apply
alter table public.alerts add column notified_at timestamptz;
alter table public.profiles add column plus_interest boolean not null default false;
-- people may only resolve their alerts; notified_at is set by the push function
revoke update on public.alerts from authenticated;
grant update (status, resolved_at) on public.alerts to authenticated;

-- plans: "where I'm going and who with", visible to circle mates until it expires
create table public.plans (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  place text check (place is null or char_length(place) <= 100),
  with_whom text check (with_whom is null or char_length(with_whom) <= 100),
  message text check (message is null or char_length(message) <= 140),
  lat double precision, lng double precision,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  check (place is not null or with_whom is not null),
  check (expires_at <= created_at + interval '49 hours')
);
create or replace function private.plans_stamp() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.created_at := now();
  delete from public.plans where expires_at < now() - interval '1 hour';
  return new;
end $$;
create trigger plans_stamp before insert or update on public.plans for each row execute function private.plans_stamp();
alter table public.plans enable row level security;
create policy "see own and active circle plans" on public.plans for select to authenticated
  using (user_id = (select auth.uid()) or (expires_at > now() and private.shares_circle(user_id)));
create policy "post own plan" on public.plans for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "update own plan" on public.plans for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "delete own plan" on public.plans for delete to authenticated
  using (user_id = (select auth.uid()));
alter publication supabase_realtime add table public.plans;
