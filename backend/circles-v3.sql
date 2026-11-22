-- Shecurity circles, version 3 (2026-11-22). Run once in the Supabase SQL editor, after
-- schema.sql, circles-groups.sql and two-way-circles.sql (all already live). Safe to run again.
--
-- How circles work now:
--   * Everyone has one big circle ("Your circle"), made automatically. At first it's just her.
--   * The big circle is always two-way: if Mia is in Ava's big circle, Ava is in Mia's. The database
--     keeps it that way by itself, whatever the app does.
--   * Small circles (Family, Best friends...) belong to the person who made them. They are her own
--     lists, picked from her big circle. Only she sees them; the people in them just get what she
--     sends to that circle.
--   * Joining with an invite code (big or small circle) puts the two of you in each other's big circle.
--     A small-circle code also puts her in that small circle.
--   * Taking someone out of your big circle takes you out of theirs, and out of all small circles
--     on both sides. Blocking does the same.
--   * Alerts, plans and live location sent to "everyone" reach your big circle; sent to a small
--     circle, only the people in it.

-- ---------- helpers ----------
create or replace function private.main_of(p_user uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select id from public.circles where owner_id = p_user and is_main;
$$;

-- is "other" in my big circle (and so me in theirs)
create or replace function private.shares_circle(other uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select other is distinct from (select auth.uid()) and exists (
    select 1 from public.circle_members m join public.circles c on c.id = m.circle_id
    where c.owner_id = (select auth.uid()) and c.is_main and m.user_id = other
  );
$$;

-- may I see something "sender" sent to circle c (null or her big circle = everyone)
create or replace function private.can_see(sender uuid, c uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select case
    when sender = (select auth.uid()) then true
    when c is null or c = private.main_of(sender) then private.shares_circle(sender)
    else private.shares_circle(sender) and exists (
      select 1 from public.circle_members m join public.circles x on x.id = m.circle_id
      where x.id = c and x.owner_id = sender and m.user_id = (select auth.uid()))
  end;
$$;

-- a circle I made
create or replace function private.owns(c uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.circles where id = c and owner_id = (select auth.uid()));
$$;
grant execute on function private.main_of(uuid), private.shares_circle(uuid), private.can_see(uuid, uuid), private.owns(uuid) to authenticated;

-- ---------- keep the rules true inside the database ----------
create or replace function private.members_before_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
declare c public.circles;
begin
  select * into c from public.circles where id = new.circle_id;
  if c.id is null or new.user_id = c.owner_id then return new; end if;
  if exists (select 1 from public.circle_members where circle_id = new.circle_id and user_id = new.user_id) then return null; end if;
  if c.is_main then
    if (select count(*) from public.circle_members where circle_id = c.id) >= 51 then
      raise exception 'This circle is full (50 people)';
    end if;
  else
    if not exists (select 1 from public.circle_members m join public.circles o on o.id = m.circle_id
                   where o.owner_id = c.owner_id and o.is_main and m.user_id = new.user_id) then
      raise exception 'Add this person to your circle first';
    end if;
    if (select count(*) from public.circle_members where circle_id = c.id) >= 26 then
      raise exception 'This circle is full (25 people)';
    end if;
  end if;
  return new;
end $$;

create or replace function private.ensure_main(p_user uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  cid uuid; code text; nm text;
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  select id into cid from public.circles where owner_id = p_user and is_main;
  if cid is not null then
    insert into public.circle_members(circle_id, user_id) values (cid, p_user) on conflict do nothing;
    return cid;
  end if;
  if not exists (select 1 from auth.users where id = p_user) then return null; end if;
  loop
    code := '';
    for i in 1..8 loop code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
    exit when not exists (select 1 from public.circles where invite_code = code);
  end loop;
  select left(coalesce(nullif(trim(display_name), ''), 'My') || '''s circle', 40) into nm from public.profiles where id = p_user;
  insert into public.circles(name, owner_id, invite_code, is_main) values (coalesce(nm, 'My circle'), p_user, code, true)
    on conflict do nothing returning id into cid;
  if cid is null then select id into cid from public.circles where owner_id = p_user and is_main; end if;
  insert into public.circle_members(circle_id, user_id) values (cid, p_user) on conflict do nothing;
  return cid;
end $$;
revoke all on function private.ensure_main(uuid) from public, anon, authenticated;

-- in her big circle means she has you in hers too
create or replace function private.members_after_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
declare c public.circles; theirs uuid;
begin
  select * into c from public.circles where id = new.circle_id;
  if c.id is null or not c.is_main or new.user_id = c.owner_id then return null; end if;
  theirs := private.ensure_main(new.user_id);
  if theirs is not null then
    insert into public.circle_members(circle_id, user_id) values (theirs, c.owner_id) on conflict do nothing;
  end if;
  return null;
end $$;

-- you can't be taken out of a circle you made (unless the circle or your account is being deleted)
create or replace function private.members_before_delete() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.circles where id = old.circle_id and owner_id = old.user_id)
     and exists (select 1 from auth.users where id = old.user_id) then
    return null;
  end if;
  return old;
end $$;

-- out of her big circle: out of each other's big and small circles, both ways
create or replace function private.members_after_delete() returns trigger
language plpgsql security definer set search_path = '' as $$
declare c public.circles;
begin
  select * into c from public.circles where id = old.circle_id;
  if c.id is null or not c.is_main or old.user_id = c.owner_id then return null; end if;
  delete from public.circle_members m using public.circles o
    where m.circle_id = o.id and o.owner_id = old.user_id and m.user_id = c.owner_id;
  delete from public.circle_members m using public.circles o
    where m.circle_id = o.id and o.owner_id = c.owner_id and not o.is_main and m.user_id = old.user_id;
  return null;
end $$;

drop trigger if exists members_before_insert on public.circle_members;
drop trigger if exists members_after_insert on public.circle_members;
drop trigger if exists members_before_delete on public.circle_members;
drop trigger if exists members_after_delete on public.circle_members;
create trigger members_before_insert before insert on public.circle_members for each row execute function private.members_before_insert();
create trigger members_after_insert after insert on public.circle_members for each row execute function private.members_after_insert();
create trigger members_before_delete before delete on public.circle_members for each row execute function private.members_before_delete();
create trigger members_after_delete after delete on public.circle_members for each row execute function private.members_after_delete();

-- nobody changes which circle a membership belongs to
revoke update on public.circle_members from authenticated, anon;
revoke update on public.circles from authenticated, anon;

-- everyone gets her big circle the moment she joins Shecurity
create or replace function private.profile_main() returns trigger
language plpgsql security definer set search_path = '' as $$
begin perform private.ensure_main(new.id); return null; end $$;
drop trigger if exists profile_main on public.profiles;
create trigger profile_main after insert on public.profiles for each row execute function private.profile_main();

-- ---------- clean up what is there today ----------
-- 1. a big circle for everyone
select private.ensure_main(id) from public.profiles;
-- 2. everyone who ever joined someone's circle: the two of them are in each other's big circle
insert into public.circle_members(circle_id, user_id)
  select distinct private.main_of(c.owner_id), m.user_id
  from public.circle_members m join public.circles c on c.id = m.circle_id
  where m.user_id <> c.owner_id and private.main_of(c.owner_id) is not null
on conflict do nothing;
insert into public.circle_members(circle_id, user_id)
  select distinct private.main_of(m.user_id), c.owner_id
  from public.circle_members m join public.circles c on c.id = m.circle_id
  where m.user_id <> c.owner_id and c.is_main and private.main_of(m.user_id) is not null
on conflict do nothing;
-- 3. owners are always in their own circles
insert into public.circle_members(circle_id, user_id) select id, owner_id from public.circles on conflict do nothing;

-- ---------- who sees what ----------
drop policy if exists "members see circle" on public.circles;
drop policy if exists "owner sees circle" on public.circles;
create policy "owner sees circle" on public.circles for select to authenticated
  using (owner_id = (select auth.uid()));
drop policy if exists "owner deletes circle" on public.circles;
create policy "owner deletes circle" on public.circles for delete to authenticated
  using (owner_id = (select auth.uid()) and not is_main);

drop policy if exists "members see members" on public.circle_members;
drop policy if exists "owner sees members, you see yourself" on public.circle_members;
create policy "owner sees members, you see yourself" on public.circle_members for select to authenticated
  using (user_id = (select auth.uid()) or private.owns(circle_id));
drop policy if exists "leave or remove" on public.circle_members;
create policy "leave or remove" on public.circle_members for delete to authenticated
  using (user_id <> (select auth.uid()) and private.owns(circle_id)
         or user_id = (select auth.uid()) and not private.owns(circle_id));

-- sending to a circle: only one of your own
drop policy if exists "send own alerts" on public.alerts;
create policy "send own alerts" on public.alerts for insert to authenticated
  with check (sender_id = (select auth.uid()) and (circle_id is null or private.owns(circle_id)));
drop policy if exists "share own location" on public.live_locations;
create policy "share own location" on public.live_locations for insert to authenticated
  with check (user_id = (select auth.uid()) and (circle_id is null or private.owns(circle_id)));
drop policy if exists "update own location" on public.live_locations;
create policy "update own location" on public.live_locations for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()) and (circle_id is null or private.owns(circle_id)));
drop policy if exists "post own plan" on public.plans;
create policy "post own plan" on public.plans for insert to authenticated
  with check (user_id = (select auth.uid()) and (circle_id is null or private.owns(circle_id)));
drop policy if exists "update own plan" on public.plans;
create policy "update own plan" on public.plans for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()) and (circle_id is null or private.owns(circle_id)));

-- responding: only to alerts you can see (the select policy already uses can_see)
drop policy if exists "respond to circle alerts" on public.alert_responses;
create policy "respond to circle alerts" on public.alert_responses for insert to authenticated
  with check (user_id = (select auth.uid()) and exists (
    select 1 from public.alerts a where a.id = alert_id and a.sender_id <> (select auth.uid()) and private.can_see(a.sender_id, a.circle_id)));

-- ---------- what the circle may see during an SOS ----------
-- shares: what she chose to share, e.g. {"location":true,"live":true,"audio":true,"battery":true}
alter table public.alerts add column if not exists shares jsonb;
-- live location can be the always-on map sharing or an SOS
alter table public.live_locations add column if not exists sos boolean not null default false;

-- ---------- functions the app calls ----------
-- everything about my circles in one go
create or replace function public.my_network() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); main uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  main := private.ensure_main(me);
  return jsonb_build_object(
    'main', (select jsonb_build_object('id', c.id, 'name', c.name, 'invite_code', c.invite_code) from public.circles c where c.id = main),
    'people', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'display_name', p.display_name, 'phone', p.phone, 'since', m.joined_at) order by p.display_name)
                        from public.circle_members m join public.profiles p on p.id = m.user_id
                        where m.circle_id = main and m.user_id <> me), '[]'::jsonb),
    'circles', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'invite_code', c.invite_code,
                           'members', coalesce((select jsonb_agg(m.user_id) from public.circle_members m where m.circle_id = c.id and m.user_id <> me), '[]'::jsonb))
                           order by c.created_at)
                         from public.circles c where c.owner_id = me and not c.is_main), '[]'::jsonb)
  );
end $$;

-- join with a code: big circle on both sides, plus the small circle if it was a small-circle code.
-- Returns the circle with its owner, so the app can offer to put her in one of your small circles.
create or replace function public.join_circle(p_code text) returns public.circles
language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); c public.circles; theirs uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into c from public.circles where invite_code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if c.id is null then raise exception 'That invite code was not found'; end if;
  if c.owner_id = me then raise exception 'This is your own invite. Send it to someone you trust.'; end if;
  perform private.ensure_main(me);
  theirs := private.ensure_main(c.owner_id);
  insert into public.circle_members(circle_id, user_id) values (theirs, me) on conflict do nothing;
  if not c.is_main then
    insert into public.circle_members(circle_id, user_id) values (c.id, me) on conflict do nothing;
  end if;
  return c;
end $$;

-- the person who invited her, for "who's this?" before joining (name only)
create or replace function public.invite_info(p_code text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('name', p.display_name, 'small', not c.is_main, 'circle', case when c.is_main then null else c.name end)
  from public.circles c join public.profiles p on p.id = c.owner_id
  where c.invite_code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

create or replace function public.main_circle(p_name text) returns public.circles
language plpgsql security definer set search_path = '' as $$
declare c public.circles;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into c from public.circles where id = private.ensure_main(auth.uid());
  return c;
end $$;

create or replace function public.create_circle(p_name text) returns public.circles
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid(); code text; c public.circles;
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  if me is null then raise exception 'not signed in'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Give your circle a name.'; end if;
  if (select count(*) from public.circles where owner_id = me and not is_main) >= 10 then raise exception 'You can make up to 10 small circles'; end if;
  perform private.ensure_main(me);
  loop
    code := '';
    for i in 1..8 loop code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
    exit when not exists (select 1 from public.circles where invite_code = code);
  end loop;
  insert into public.circles(name, owner_id, invite_code) values (left(trim(p_name), 40), me, code) returning * into c;
  insert into public.circle_members(circle_id, user_id) values (c.id, me);
  return c;
end $$;

create or replace function public.rename_circle(p_circle uuid, p_name text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(trim(p_name), '') = '' then raise exception 'Give your circle a name.'; end if;
  update public.circles set name = left(trim(p_name), 40) where id = p_circle and owner_id = auth.uid() and not is_main;
  if not found then raise exception 'Only the person who made this circle can do this'; end if;
end $$;

-- put someone from your big circle in one of your small circles, or take them out
create or replace function public.set_in_circle(p_circle uuid, p_user uuid, p_in boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare c public.circles;
begin
  select * into c from public.circles where id = p_circle;
  if c.id is null or c.owner_id <> auth.uid() or c.is_main then raise exception 'Only the person who made this circle can do this'; end if;
  if p_user = auth.uid() then return; end if;
  if p_in then
    insert into public.circle_members(circle_id, user_id) values (p_circle, p_user) on conflict do nothing;
  else
    delete from public.circle_members where circle_id = p_circle and user_id = p_user;
  end if;
end $$;

-- older app versions
create or replace function public.move_member(p_user uuid, p_from uuid, p_to uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.owns(p_to) or (p_from is not null and not private.owns(p_from)) then raise exception 'Only the person who made this circle can do this'; end if;
  insert into public.circle_members(circle_id, user_id) values (p_to, p_user) on conflict do nothing;
  if p_from is not null and p_from <> p_to then delete from public.circle_members where circle_id = p_from and user_id = p_user; end if;
end $$;

-- take someone out of a circle you made; out of your big circle means out of everything, both ways
create or replace function public.remove_member(p_circle uuid, p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.owns(p_circle) then raise exception 'Only the person who made this circle can do this'; end if;
  if p_user = auth.uid() then raise exception 'You can''t remove yourself'; end if;
  delete from public.circle_members where circle_id = p_circle and user_id = p_user;
end $$;

-- you and her are no longer in each other's circles
create or replace function public.unlink(p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  delete from public.circle_members where circle_id = private.main_of(auth.uid()) and user_id = p_user and p_user <> auth.uid();
  delete from public.circle_members where circle_id = private.main_of(p_user) and user_id = auth.uid() and p_user <> auth.uid();
end $$;

create or replace function public.leave_circle(p_circle uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare c public.circles;
begin
  select * into c from public.circles where id = p_circle;
  if c.id is null then return; end if;
  if c.owner_id = auth.uid() then raise exception 'You made this circle; delete it instead'; end if;
  if c.is_main then perform public.unlink(c.owner_id);
  else delete from public.circle_members where circle_id = p_circle and user_id = auth.uid(); end if;
end $$;

-- for the push functions (service role only): who gets an alert
create or replace function public.alert_audience(p_alert uuid) returns setof uuid
language sql stable security definer set search_path = '' as $$
  select m.user_id from public.alerts a
  join public.circle_members m on m.circle_id = coalesce(
    case when a.circle_id is not null and exists (select 1 from public.circles x where x.id = a.circle_id and x.owner_id = a.sender_id) then a.circle_id end,
    private.main_of(a.sender_id))
  where a.id = p_alert and m.user_id <> a.sender_id
    and exists (select 1 from public.circle_members b join public.circles o on o.id = b.circle_id
                where o.owner_id = a.sender_id and o.is_main and b.user_id = m.user_id);
$$;
create or replace function public.user_audience(p_user uuid) returns setof uuid
language sql stable security definer set search_path = '' as $$
  select m.user_id from public.circle_members m where m.circle_id = private.main_of(p_user) and m.user_id <> p_user;
$$;

revoke all on function public.my_network(), public.join_circle(text), public.invite_info(text), public.main_circle(text), public.create_circle(text),
  public.rename_circle(uuid, text), public.set_in_circle(uuid, uuid, boolean), public.move_member(uuid, uuid, uuid),
  public.remove_member(uuid, uuid), public.unlink(uuid), public.leave_circle(uuid), public.alert_audience(uuid), public.user_audience(uuid) from public, anon;
grant execute on function public.my_network(), public.join_circle(text), public.invite_info(text), public.main_circle(text), public.create_circle(text),
  public.rename_circle(uuid, text), public.set_in_circle(uuid, uuid, boolean), public.move_member(uuid, uuid, uuid),
  public.remove_member(uuid, uuid), public.unlink(uuid), public.leave_circle(uuid) to authenticated;
revoke execute on function public.alert_audience(uuid), public.user_audience(uuid) from authenticated;
grant execute on function public.alert_audience(uuid), public.user_audience(uuid) to service_role;

-- the app updates when someone joins or leaves
do $$ begin
  alter publication supabase_realtime add table public.circle_members;
exception when duplicate_object then null; end $$;

-- ---------- SOS sound clips ----------
-- private storage: clips live in <her id>/<alert id>/..., and only people who can see that alert can play them
insert into storage.buckets (id, name, public, file_size_limit)
  values ('sos-audio', 'sos-audio', false, 5242880)
  on conflict (id) do update set public = false, file_size_limit = 5242880;

create or replace function private.can_hear(p_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.alerts a
    where a.id::text = split_part(p_name, '/', 2) and a.sender_id::text = split_part(p_name, '/', 1)
      and (a.sender_id = (select auth.uid()) or private.can_see(a.sender_id, a.circle_id)));
$$;
grant execute on function private.can_hear(text) to authenticated;

drop policy if exists "sos audio upload" on storage.objects;
create policy "sos audio upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'sos-audio' and split_part(name, '/', 1) = (select auth.uid())::text and private.can_hear(name));
drop policy if exists "sos audio listen" on storage.objects;
create policy "sos audio listen" on storage.objects for select to authenticated
  using (bucket_id = 'sos-audio' and private.can_hear(name));
drop policy if exists "sos audio delete own" on storage.objects;
create policy "sos audio delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'sos-audio' and split_part(name, '/', 1) = (select auth.uid())::text);
