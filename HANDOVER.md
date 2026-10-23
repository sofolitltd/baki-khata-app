# Baki Khata — handover (2026-10-23)

No secrets in this file. Secrets live in `baki-khata-api/.env*`, Vercel env vars, and `~/.baki_khata/`.

## What it is
Bangla shop-credit ledger. Android app (Flutter, offline-first SQLite) + sync API/website (Go). Brand: **Baki Khata** (landing footer says "বাকির খাতা · Powered By: Sofol IT" — user's wording).

## Layout (all under `/Users/reyad/Documents/Programming/Flutter/`)
| Path | What | GitHub |
|---|---|---|
| `baki-khata-app/` | Flutter app | `sofolitltd/baki-khata-app` (PUBLIC) |
| `baki-khata-api/` | Go + Gin + Neon Postgres API, landing page at `/` | `sofolitltd/baki-khata-api` (private) |

Dart package name `baki_khata` and Android `applicationId` `com.sofolit.baki_khata` are deliberately NOT renamed (would break updates / hyphens illegal).

## Live
- Site + API: https://bakikhatabd.vercel.app (primary). `baki-khata-api-silk.vercel.app` also works (redirect removed on purpose: Dart does not follow 307 on POST, v1.0.1 apps use it).
- `bakikhata.vercel.app` is taken by someone else's "Coming Soon" project; couldn't be claimed.
- Vercel: scope/team `sofolit` (SofolIT), project `baki-khata-api`, container deploy (`Dockerfile.vercel`), region `sin1`, GitHub-connected: **push to `main` auto-deploys**. CLI login must be the Sofolit account (`vercel login`, device flow); `gadget-doptor` team has an OLD `baki-khata-api` project that still needs deleting (not reachable with the current login).
- Neon DB branch `production` (ap-southeast-1). Env on Vercel: `DATABASE_URL`, `JWT_SECRET` (production only).
- Latest release: v1.0.3 (https://github.com/sofolitltd/baki-khata-app/releases). Site's Download button -> `/download` -> 302 to `releases/latest/download/baki-khata.apk`.

## Run locally
- `baki-khata-app`: `make run-e` (emulator-5554, API at 10.0.2.2:8080), `make run-d [DEVICE=id]` (real phone via LAN IP), `make run` (starts API), `make devices`.
- `baki-khata-api`: `make run` (kills old process on :8080 first), `make landing` / `npm run landing` rebuilds `landing/app.css` (Tailwind v4 CLI) — **commit the built `app.css`**.
- Debug builds use localhost/10.0.2.2; **release builds default to `bakikhatabd.vercel.app`** (`lib/config.dart`), override with `--dart-define=API_URL=`.

## Release procedure (app)
1. Bump `version:` in `pubspec.yaml` (currently 1.0.3+4).
2. `flutter build apk --release --split-per-abi` (~3 min; run in background).
3. Verify signature: `apksigner verify --print-certs` -> `CN=Baki Khata, O=Sofolit`.
4. Copy to `baki-khata-vX.Y.Z-{arm64-v8a,armeabi-v7a,x86_64}.apk`, **plus `baki-khata.apk` (= arm64) — required, the website download link depends on this exact name**, plus `SHA256SUMS.txt`.
5. `git tag -a vX.Y.Z`, push `main` + tag, `gh release create vX.Y.Z ... --latest`.
Signing: `android/key.properties` (gitignored) -> `~/.baki_khata/upload-keystore.jks`. **Back this up off-machine; losing it means no more updates for installed apps.** Without key.properties the build silently signs with the debug key.

## Architecture notes
- Notifications are 100% local (`flutter_local_notifications`, scheduled from SQLite data; daily 9:00 summary for next 7 days). No FCM/server push.
- Sync: `lib/sync.dart`. PIN is kept in `flutter_secure_storage` so the app can (re)login silently (offline-at-login, expired 90-day JWT). Wrong PIN clears it and the sheet asks for PIN once. Sheet shows last sync time (persisted) + pushed/pulled counts.
- Auth lockout server-side: 5 wrong PINs -> 15 min lock. bcrypt PIN hashes.
- Voice (v1.0.3): `lib/voice.dart` — TTS (`flutter_tts`, bn-BD, Bangla number words) on home hero + customer screen; `MicButton` (`speech_to_text`) on customers search, entry amount (parses spoken Bangla numbers), note, name. Needs RECORD_AUDIO (declared). Depends on Google speech/TTS having Bangla on the device.
- Calls/SMS go through `callPhone`/`sendSms` in `lib/utils.dart` (manifest `<queries>` for tel/sms/RecognitionService already present).
- Landing is embedded in the Go binary (`landing.go`, `go:embed`). **`Dockerfile.vercel` copies landing files explicitly — add any new landing file there and to the embed directive.** Gin `GET` routes don't answer HEAD (use GET when testing).
- Same Neon DB is used by local API runs and prod — don't write demo data through the API.

## Gotchas hit this session
- `vercel link` appended a `VERCEL_OIDC_TOKEN` to `baki-khata-api/.env.local` (gitignored; DB vars intact).
- The emulator (`emulator-5554`) holds the user's real test data incl. a profile with a real-looking name/shop/address — don't screenshot the profile screen. The demo-data trick used for landing screenshots: pull `databases/baki_khata.db` via `adb run-as`, edit with python sqlite3 (`dirty=0`), push back, restore the backup afterwards. `adb` is not on PATH: `$ANDROID_SDK/platform-tools/adb` (sdk.dir in `android/local.properties`).
- Mic permission on the emulator was revoked after testing.

## Not verified / open
- Never installed the release APKs on a real phone; real-device voice (Bangla STT/TTS quality) untested.
- Landing page checked at desktop width only (headless Chrome can't do narrow widths).
- Old `gadget-doptor` Vercel project still exists (see above). Old releases v1.0.0 (points to dead-to-be old URL) and v1.0.1 still listed.
- `baki-khata-api` repo is private (fine). Local `.iml` files still carry old names (IDE-generated).
- Ideas not started: voice settings toggle, exact-time alarms (`SCHEDULE_EXACT_ALARM`), FCM push, rate limiting beyond per-account lockout.
