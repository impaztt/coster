# Cloudflare Pages Deployment

One-time setup to publish the Flutter web build from GitHub to Cloudflare Pages.

## 1. Connect the repo

1. Open https://dash.cloudflare.com/ → **Workers & Pages** → **Create** → **Pages** → **Connect to Git**.
2. Authorize Cloudflare for GitHub if needed, select the `sw_clicker` repo, **Begin setup**.

## 2. Build configuration

Fill in exactly:

| Field | Value |
| --- | --- |
| Project name | anything (e.g. `sw-clicker`) — becomes the subdomain on `*.pages.dev` |
| Production branch | `main` |
| Framework preset | **None** |
| Build command | `bash cloudflare-pages-build.sh` |
| Build output directory | `build/web` |
| Root directory | *(leave blank)* |

### Environment variables (optional)

Add these under **Environment variables → Production & Preview** if you want to override defaults:

| Name | Default | Purpose |
| --- | --- | --- |
| `FLUTTER_CHANNEL` | `stable` | Pin channel (`stable` / `beta`) |
| `FLUTTER_VERSION` | *(unused)* | *(not read by the current script — add if you want a pinned version)* |

## 3. Deploy

Click **Save and Deploy**. First build runs ~2–4 min (Flutter clone + pub get + release build). Subsequent builds are similar — Cloudflare's cache doesn't help much for Flutter SDK, but the build is fast enough.

Your production URL will be `https://<project-name>.pages.dev`.

## 4. Verify

- Open the URL on desktop Chrome — app loads, clicks register.
- Open DevTools → Application → Local Storage → check `sb-...-auth-token` exists (Supabase anon session) and `sw_clicker_save_v1` appears after a save tick.
- Open the same URL in a different browser (or incognito) — should get a different anon account with a fresh save.
- Supabase Dashboard → Table Editor → `SW_saves` — one row per anon user.

## 5. Updating

Just `git push origin main`. Cloudflare builds and deploys automatically. Preview deployments are generated for non-main branches and PRs.

## Caveats

- **Public URL**: anyone with the link can play. Each visitor creates an anonymous Supabase user. Free tier tolerates this (50k MAU), but if you want to gate testers, add a simple password screen in-app or restrict the URL via Cloudflare Access.
- **Supabase Redirect URLs**: not required for anonymous auth. Once you add Google OAuth, whitelist the Cloudflare URL in Supabase Dashboard → Authentication → URL Configuration.
- **Custom domain**: Cloudflare Pages → your project → **Custom domains** → add domain. Works with any Cloudflare-managed domain instantly; external DNS needs a CNAME.
- **Mobile browsers**: touch + audio work, but the HTML5 canvas renderer may feel heavier than the native app. This is testing-only.
