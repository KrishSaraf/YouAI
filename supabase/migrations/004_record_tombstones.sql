-- A deleted log keeps its row with deleted_at set, so a phone that still has a
-- copy removes it on the next sync instead of uploading it again.

alter table public.user_records
  add column if not exists deleted_at timestamptz;
