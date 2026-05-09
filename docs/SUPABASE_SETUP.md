# Supabase Cloud Save Setup

Run the following SQL in the Supabase SQL Editor once per project
(Dashboard → SQL Editor → New query).

```sql
-- Single save row per user. Entire SaveData JSON lives in `data`.
create table if not exists public."SW_saves" (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  data          jsonb       not null,
  last_saved_at timestamptz not null,
  updated_at    timestamptz not null default now()
);

-- Keep updated_at fresh on every write.
create or replace function public.sw_saves_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists sw_saves_touch_updated_at on public."SW_saves";
create trigger sw_saves_touch_updated_at
  before update on public."SW_saves"
  for each row execute function public.sw_saves_touch_updated_at();

-- Row-Level Security: a user may only touch their own row.
alter table public."SW_saves" enable row level security;

drop policy if exists "own row select" on public."SW_saves";
create policy "own row select" on public."SW_saves"
  for select using (auth.uid() = user_id);

drop policy if exists "own row insert" on public."SW_saves";
create policy "own row insert" on public."SW_saves"
  for insert with check (auth.uid() = user_id);

drop policy if exists "own row update" on public."SW_saves";
create policy "own row update" on public."SW_saves"
  for update using (auth.uid() = user_id)
              with check (auth.uid() = user_id);
```

## Save safety hardening (recommended)

Once the base table above exists, run [`sql/save_safety.sql`](sql/save_safety.sql)
in the SQL Editor. It adds:

- **Stale-write rejection** on `SW_saves` — an `UPDATE` whose `last_saved_at`
  is older than the existing row is rejected with `P0001 stale_save`.
- **Rolling snapshot history** in a new `SW_save_backups` table — the row
  state being replaced is archived (max 1/hour/user, last 24 retained per
  user). RLS is read-own only; clients cannot insert/delete, so the history
  is tamper-resistant.

The file is idempotent — safe to re-run.

## Dashboard settings

- **Authentication → Providers → Anonymous Sign-ins**: must be **Enabled**.
  (Already confirmed on.)

## How sync works

- On app start, `SyncService.loadResolved()` signs in anonymously (or
  resumes the existing session), fetches the cloud row, and picks whichever
  side has the newer `lastSavedAt`. If cloud wins, local is overwritten
  with the cloud copy (preserving its timestamp).
- Every local save (auto-save tick, app-pause, prestige) pushes to the
  cloud in the background. Network failures are swallowed — the next
  persist will catch up.
- `resetAll()` wipes local and pushes the fresh state so other devices
  see the reset on their next boot.

## Next steps (not implemented yet)

1. **Google Sign-In linking (Android)** — use `google_sign_in` +
   `supabase.auth.signInWithIdToken(provider: OAuthProvider.google, ...)`,
   or `supabase.auth.linkIdentity(OAuthProvider.google)` to bind the
   anonymous user to a Google account. Requires a Web Client ID from
   Google Cloud Console and the Android SHA-1 registered there.
2. **Game Center (iOS)** — requires `flutter create --platforms=ios .`
   first. Supabase has no first-party Game Center provider, so this
   typically means a Sign-In-with-Apple fallback or a custom JWT flow.
