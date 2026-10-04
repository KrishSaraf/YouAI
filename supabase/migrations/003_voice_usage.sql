-- Daily cap for spoken logs. Separate from photo estimates.

create table public.voice_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  count integer not null default 0 check (count >= 0),
  primary key (user_id, day)
);

alter table public.voice_usage enable row level security;

create or replace function public.consume_voice_credit(target_user uuid, daily_limit integer)
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

  insert into public.voice_usage as usage (user_id, day, count)
  values (target_user, (timezone('utc', now()))::date, 1)
  on conflict (user_id, day)
    do update set count = usage.count + 1
    where usage.count < daily_limit
    returning count into current_count;

  return current_count is not null;
end;
$$;

revoke all on function public.consume_voice_credit(uuid, integer) from public, anon, authenticated;
grant execute on function public.consume_voice_credit(uuid, integer) to service_role;
