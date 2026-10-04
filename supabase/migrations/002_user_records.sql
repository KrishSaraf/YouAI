-- Logs that belong to a signed-in account: meals, workouts, habits, and
-- the weight, water, sleep, and vitals entered in the app.

create table public.user_records (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);

create index user_records_user_idx on public.user_records (user_id);

alter table public.user_records enable row level security;

create policy "Own records"
  on public.user_records
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update, delete on public.user_records to authenticated;
