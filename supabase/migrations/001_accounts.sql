-- Run once in the Supabase SQL editor.
-- Accounts themselves live in Supabase Auth (Apple, Google, and email).
-- This adds the photo quota those accounts share.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Read your own profile"
  on public.profiles
  for select
  to authenticated
  using (auth.uid() = id);

create table public.photo_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  count integer not null default 0 check (count >= 0),
  primary key (user_id, day)
);

alter table public.photo_usage enable row level security;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.consume_photo_credit(target_user uuid, daily_limit integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_count integer;
begin
  if target_user is null or daily_limit < 1 then
    return false;
  end if;

  insert into public.photo_usage as usage (user_id, day, count)
  values (target_user, (timezone('utc', now()))::date, 1)
  on conflict (user_id, day)
  do update set count = photo_usage.count + 1
  where photo_usage.count < daily_limit
  returning count into current_count;

  return current_count is not null;
end;
$$;

revoke all on function public.consume_photo_credit(uuid, integer) from public, anon, authenticated;
grant execute on function public.consume_photo_credit(uuid, integer) to service_role;
