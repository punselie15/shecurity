-- Small circles inside one big circle (2026-10-26).
-- "Everyone" is all the people in all your circles. An alert, a live location or a plan can go to
-- everyone (circle_id null, as before) or to one small circle. Older app versions keep sending to everyone.

-- your own "everyone only" circle: people you add to the big circle without a small one
alter table public.circles add column if not exists is_main boolean not null default false;
create unique index if not exists circles_one_main on public.circles(owner_id) where is_main;

alter table public.alerts add column if not exists circle_id uuid references public.circles(id) on delete cascade;
alter table public.live_locations add column if not exists circle_id uuid references public.circles(id) on delete cascade;
alter table public.plans add column if not exists circle_id uuid references public.circles(id) on delete cascade;
create index if not exists alerts_circle_idx on public.alerts(circle_id);

-- who may see something sent to everyone, or to one circle
create or replace function private.can_see(sender uuid, c uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select case when c is null then private.shares_circle(sender)
              else exists (select 1 from public.circle_members a join public.circle_members b on a.circle_id = b.circle_id
                           where a.circle_id = c and a.user_id = (select auth.uid()) and b.user_id = sender) end;
$$;
grant execute on function private.can_see(uuid, uuid) to authenticated;

drop policy if exists "send own alerts" on public.alerts;
create policy "send own alerts" on public.alerts for insert to authenticated
  with check (sender_id = (select auth.uid()) and (circle_id is null or private.is_member(circle_id)));
drop policy if exists "see own and circle alerts" on public.alerts;
create policy "see own and circle alerts" on public.alerts for select to authenticated
  using (sender_id = (select auth.uid()) or private.can_see(sender_id, circle_id));

drop policy if exists "see own and active circle locations" on public.live_locations;
create policy "see own and active circle locations" on public.live_locations for select to authenticated
  using (user_id = (select auth.uid()) or (sharing_until > now() and private.can_see(user_id, circle_id)));
drop policy if exists "share own location" on public.live_locations;
create policy "share own location" on public.live_locations for insert to authenticated
  with check (user_id = (select auth.uid()) and (circle_id is null or private.is_member(circle_id)));
drop policy if exists "update own location" on public.live_locations;
create policy "update own location" on public.live_locations for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()) and (circle_id is null or private.is_member(circle_id)));

drop policy if exists "see own and active circle plans" on public.plans;
create policy "see own and active circle plans" on public.plans for select to authenticated
  using (user_id = (select auth.uid()) or (expires_at > now() and private.can_see(user_id, circle_id)));
drop policy if exists "post own plan" on public.plans;
create policy "post own plan" on public.plans for insert to authenticated
  with check (user_id = (select auth.uid()) and (circle_id is null or private.is_member(circle_id)));
drop policy if exists "update own plan" on public.plans;
create policy "update own plan" on public.plans for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()) and (circle_id is null or private.is_member(circle_id)));

-- your "everyone only" circle, made the first time you invite someone to just the big circle
create or replace function public.main_circle(p_name text) returns public.circles
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  c public.circles;
  code text;
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into c from public.circles where owner_id = me and is_main;
  if c.id is not null then return c; end if;
  loop
    code := '';
    for i in 1..8 loop code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
    exit when not exists (select 1 from public.circles where invite_code = code);
  end loop;
  insert into public.circles(name, owner_id, invite_code, is_main) values (left(trim(coalesce(nullif(p_name, ''), 'My circle')), 40), me, code, true) returning * into c;
  insert into public.circle_members(circle_id, user_id) values (c.id, me);
  return c;
end $$;
revoke all on function public.main_circle(text) from public, anon;
grant execute on function public.main_circle(text) to authenticated;

-- move someone you added between your circles (you own both), without a new invite
create or replace function public.move_member(p_user uuid, p_from uuid, p_to uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.circles where id = p_to and owner_id = auth.uid()) then raise exception 'Only the circle owner can do this'; end if;
  if p_from is not null and not exists (select 1 from public.circles where id = p_from and owner_id = auth.uid()) then raise exception 'Only the circle owner can do this'; end if;
  if not private.shares_circle(p_user) then raise exception 'This person is not in your circle'; end if;
  if (select count(*) from public.circle_members where circle_id = p_to) >= 25 then raise exception 'This circle is full (25 people)'; end if;
  insert into public.circle_members(circle_id, user_id) values (p_to, p_user) on conflict do nothing;
  if p_from is not null and p_from <> p_to then delete from public.circle_members where circle_id = p_from and user_id = p_user; end if;
end $$;
revoke all on function public.move_member(uuid, uuid, uuid) from public, anon;
grant execute on function public.move_member(uuid, uuid, uuid) to authenticated;
