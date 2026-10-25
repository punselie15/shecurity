-- Shecurity: let a paired watch raise alerts. Paste into Supabase > SQL editor and press Run.
create table if not exists private.watch_keys (
  key_hash text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);
create index if not exists watch_keys_user_idx on private.watch_keys(user_id);
alter table private.watch_keys enable row level security;

-- a long-lived key the watch uses to raise alerts for its owner; only a hash is stored
create or replace function public.new_watch_key() returns text
language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); k text;
begin
  if me is null then raise exception 'not signed in'; end if;
  delete from private.watch_keys where user_id = me and key_hash not in (
    select key_hash from private.watch_keys where user_id = me order by created_at desc limit 4);
  k := 'shw_' || encode(extensions.gen_random_bytes(24), 'hex');
  insert into private.watch_keys(key_hash, user_id) values (encode(extensions.digest(k, 'sha256'), 'hex'), me);
  return k;
end $$;

create or replace function public.revoke_watch_keys() returns void
language sql security definer set search_path = '' as $$
  delete from private.watch_keys where user_id = auth.uid();
$$;

-- service role only: which user a watch key belongs to
create or replace function public.watch_key_user(p_key text) returns uuid
language sql security definer set search_path = '' as $$
  update private.watch_keys set last_used_at = now()
  where key_hash = encode(extensions.digest(p_key, 'sha256'), 'hex')
  returning user_id;
$$;

revoke all on function public.new_watch_key(), public.revoke_watch_keys(), public.watch_key_user(text) from public, anon;
grant execute on function public.new_watch_key(), public.revoke_watch_keys() to authenticated;
revoke execute on function public.watch_key_user(text) from authenticated;
grant execute on function public.watch_key_user(text) to service_role;
