-- =============================================================================
-- Save safety hardening — run once in Supabase SQL Editor.
-- Idempotent: safe to re-run.
--
-- Adds:
--   (A) BEFORE-UPDATE trigger that rejects writes whose `last_saved_at`
--       is older than what's already on the server. Stops a stale device
--       (or buggy client) from clobbering a newer save.
--   (B) `SW_save_backups` history table + AFTER-UPDATE trigger that
--       snapshots the *previous* row state (max 1 snapshot/hour/user,
--       keeping the most recent 24 per user). Used for manual recovery
--       if a save ever lands corrupted.
--
-- Prerequisite: docs/SUPABASE_SETUP.md has already been run, so
-- public."SW_saves" and its RLS policies exist.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (A) Stale-write guard on SW_saves
-- -----------------------------------------------------------------------------
create or replace function public.sw_saves_reject_stale_write()
returns trigger
language plpgsql
as $$
begin
  if new.last_saved_at < old.last_saved_at then
    raise exception
      'stale_save: incoming last_saved_at (%) older than existing (%)',
      new.last_saved_at, old.last_saved_at
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sw_saves_reject_stale on public."SW_saves";
create trigger trg_sw_saves_reject_stale
before update on public."SW_saves"
for each row execute function public.sw_saves_reject_stale_write();

-- -----------------------------------------------------------------------------
-- (B) Per-user rolling snapshot history
-- -----------------------------------------------------------------------------
create table if not exists public."SW_save_backups" (
  id            bigserial   primary key,
  user_id       uuid        not null references auth.users(id) on delete cascade,
  data          jsonb       not null,
  last_saved_at timestamptz not null,
  created_at    timestamptz not null default now()
);

create index if not exists sw_save_backups_user_idx
  on public."SW_save_backups" (user_id, created_at desc);

alter table public."SW_save_backups" enable row level security;

-- Read-own only. No INSERT/UPDATE/DELETE policy → only the SECURITY DEFINER
-- trigger and the service role can write/clean. Clients cannot tamper.
drop policy if exists "read own backups" on public."SW_save_backups";
create policy "read own backups"
  on public."SW_save_backups" for select
  using (auth.uid() = user_id);

create or replace function public.sw_saves_snapshot_on_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recent_count int;
begin
  -- Throttle: at most one snapshot per user per hour.
  select count(*) into recent_count
  from public."SW_save_backups"
  where user_id = new.user_id
    and created_at > now() - interval '1 hour';

  if recent_count = 0 then
    -- Snapshot the *previous* row (OLD) so the backup represents the state
    -- that the new write is replacing.
    insert into public."SW_save_backups" (user_id, data, last_saved_at)
    values (new.user_id, old.data, old.last_saved_at);

    -- Keep only the 24 most recent snapshots per user.
    delete from public."SW_save_backups"
    where id in (
      select id from public."SW_save_backups"
      where user_id = new.user_id
      order by created_at desc
      offset 24
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sw_saves_snapshot on public."SW_saves";
create trigger trg_sw_saves_snapshot
after update on public."SW_saves"
for each row execute function public.sw_saves_snapshot_on_change();

-- -----------------------------------------------------------------------------
-- Sanity checks (optional — run separately to verify)
-- -----------------------------------------------------------------------------
-- select tgname, tgrelid::regclass
-- from pg_trigger
-- where tgrelid = 'public."SW_saves"'::regclass
--   and not tgisinternal;
--
-- select count(*) from public."SW_save_backups";
