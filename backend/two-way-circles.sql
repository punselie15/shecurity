-- Two-way circles (2026-11-16). Run once in the Supabase SQL editor, after circles-groups.sql.
-- When she joins someone's circle with a code, the person who invited her also lands in her own
-- whole circle, so each of them has the other as "their person". Removing or leaving cuts both ways.
-- Who gets whose alerts does not change: two people who share any circle already reach each other.

-- her own "everyone only" circle, made if she has none yet (server side, for any user)
create or replace function private.ensure_main(p_user uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  cid uuid;
  code text;
  nm text;
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  select id into cid from public.circles where owner_id = p_user and is_main;
  if cid is not null then return cid; end if;
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

-- joining: she joins the circle, and the person who made it joins her whole circle
create or replace function public.join_circle(p_code text) returns public.circles
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  c public.circles;
  mine uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into c from public.circles where invite_code = upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g'));
  if c.id is null then raise exception 'That invite code was not found'; end if;
  if (select count(*) from public.circle_members where circle_id = c.id) >= 25 then raise exception 'This circle is full (25 people)'; end if;
  insert into public.circle_members(circle_id, user_id) values (c.id, me) on conflict do nothing;
  -- unless the creator is already in one of her own circles
  if c.owner_id <> me and not exists (select 1 from public.circle_members m join public.circles o on o.id = m.circle_id
                                      where o.owner_id = me and m.user_id = c.owner_id) then
    mine := private.ensure_main(me);
    if (select count(*) from public.circle_members where circle_id = mine) < 25 then
      insert into public.circle_members(circle_id, user_id) values (mine, c.owner_id) on conflict do nothing;
    end if;
  end if;
  return c;
end $$;

-- removing someone from your circle; from your whole circle it also takes you out of hers
create or replace function public.remove_member(p_circle uuid, p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare c public.circles;
begin
  select * into c from public.circles where id = p_circle;
  if c.id is null or c.owner_id <> auth.uid() then raise exception 'Only the circle owner can do this'; end if;
  if p_user = auth.uid() then raise exception 'You can''t remove yourself'; end if;
  delete from public.circle_members where circle_id = p_circle and user_id = p_user;
  if c.is_main then
    delete from public.circle_members m using public.circles o
      where m.circle_id = o.id and o.owner_id = p_user and o.is_main and m.user_id = auth.uid();
  end if;
end $$;

-- leaving someone's circle; leaving her whole circle also takes her out of yours
create or replace function public.leave_circle(p_circle uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare c public.circles;
begin
  select * into c from public.circles where id = p_circle;
  if c.id is null then return; end if;
  if c.owner_id = auth.uid() then raise exception 'You made this circle; delete it instead'; end if;
  delete from public.circle_members where circle_id = p_circle and user_id = auth.uid();
  if c.is_main then
    delete from public.circle_members m using public.circles o
      where m.circle_id = o.id and o.owner_id = auth.uid() and o.is_main and m.user_id = c.owner_id;
  end if;
end $$;

revoke all on function public.join_circle(text), public.remove_member(uuid, uuid), public.leave_circle(uuid) from public, anon;
grant execute on function public.join_circle(text), public.remove_member(uuid, uuid), public.leave_circle(uuid) to authenticated;

-- people who already joined someone: add the person who invited them to their whole circle too
do $$
declare r record; mine uuid;
begin
  for r in
    select distinct m.user_id as member, c.owner_id as owner
    from public.circle_members m join public.circles c on c.id = m.circle_id
    where m.user_id <> c.owner_id
  loop
    if exists (select 1 from public.circle_members m join public.circles o on o.id = m.circle_id
               where o.owner_id = r.member and m.user_id = r.owner) then continue; end if;
    mine := private.ensure_main(r.member);
    if (select count(*) from public.circle_members where circle_id = mine) < 25 then
      insert into public.circle_members(circle_id, user_id) values (mine, r.owner);
    end if;
  end loop;
end $$;
