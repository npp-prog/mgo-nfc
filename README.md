# MGO NFC Attendance

Office attendance using NFC tags (NTAG215). Employees tap their phone on a tag
at the office entrance to check in or out; admins register tags, manage
employees, watch a daily dashboard and export attendance to CSV for payroll.

| Part | Tech |
|---|---|
| Mobile app | Flutter (Android first, iOS later) — `app/` |
| Auth | Firebase Auth (email/password) |
| Database | Cloud Firestore — `firestore.rules`, `firestore.indexes.json` |
| Backend | Cloud Functions 2nd gen, TypeScript, Node 22 — `functions/` |

## How it works

1. Each tag holds an NDEF URL `https://<domain>/tag/<tagId>`; its factory UID is
   saved in `tags/<tagId>` when an admin registers it.
2. The app reads the UID + URL and calls the `recordAttendance` callable.
3. The function verifies the caller, checks the UID against the registered tag,
   decides **in** vs **out** from the user's last tap that day, rejects repeat
   taps within 2 minutes, and writes the record with a server timestamp.

Clients never write attendance — only Cloud Functions do.

## Repository layout

```
app/                    Flutter app
functions/              Cloud Functions (TypeScript)
  src/index.ts          function exports
firestore.rules         security rules
firestore.indexes.json  composite indexes
firebase.json           Firebase + Emulator Suite config
.firebaserc.example     copy to .firebaserc with your project ID
scripts/                emulator seed scripts
```

## Firestore schema

| Collection | Doc ID | Written by |
|---|---|---|
| `users` | Auth uid | Cloud Functions (admin actions) |
| `tags` | tagId (from the URL) | admins / `registerTag` |
| `attendance` | auto | `recordAttendance` only |
| `attendanceDays` | `{uid}_{YYYY-MM-DD}` | `recordAttendance` only |
| `settings` | `app` | admins |

`settings/app` holds `lateTime` (default `"08:00"`), `timezone`
(default `"Asia/Manila"`), `duplicateWindowSeconds` (120), `tagUrlBase` and
`workDays`.

## Prerequisites

- Node.js 22 and npm
- Java 21+ (required by the Firestore emulator)
- Flutter SDK (stable, 3.47+ / Dart 3.13+) + Android Studio / Android SDK
- An Android phone with NFC for real tag testing
- A Firebase project on the **Blaze** plan (required for Cloud Functions)

The Firebase CLI is installed locally as a dev dependency; run it with `npx firebase`.

## Local development (Emulator Suite)

```bash
npm install                    # Firebase CLI
npm --prefix functions install
npm run build:functions
npm run emulators              # Auth :9099, Firestore :8080, Functions :5001, UI :4000
```

The emulators run under the demo project ID `demo-mgo-nfc`, so nothing ever
touches a real Firebase project. Open http://127.0.0.1:4000 for the Emulator UI.
Use `npm run emulators:persist` to keep data in `./emulator-data` (git-ignored)
between runs.

With the emulators running, load demo data in a second terminal:

```bash
npm run seed
```

This creates settings, two tags (`main-entrance`, `back-door`), two weeks of
attendance generated through the real `recordAttendance` logic, and these logins:

| Role | Email | Password |
|---|---|---|
| admin | admin@example.com | admin1234 |
| employee | juan@example.com, maria@example.com, pedro@example.com | password123 |

The seed script refuses to run against anything but a `demo-*` project on the emulators.

## Try it in Chrome (no phone needed)

The quickest way to see everything working. You need Node.js 22, Java 21 and
Flutter (Android Studio is not needed for this).

```bash
npm install
npm install --prefix functions
npm run emulators        # terminal 1: leave it running
npm run seed             # terminal 2: demo users, tags and two weeks of history
npm run app:web          # terminal 2: opens the app in Chrome
```

Sign in as `juan@example.com` / `password123` (employee) or
`admin@example.com` / `admin1234` (admin). In this test mode:

- employees get **Simulate tag tap**: pick a registered tag (or a copied tag
  with the wrong UID, or some other sticker) and the app sends exactly what a
  real tap would to `recordAttendance`;
- admins get **Simulate a blank tag** on *Tags → Add tag*, which registers the
  tag and runs the real tag-writing and locking code against a simulated
  NTAG215 chip;
- the CSV export downloads the file.

The simulate buttons only exist in test mode (`USE_EMULATORS=true`), which can
only reach the local emulators, never real data. The web version doesn't run
outside test mode yet. Times are shown in the computer's time zone, so use a
computer set to the office time zone (Asia/Manila).

## Running the app

The app lives in `app/` (Flutter, package `org.mgocandoniaccounting.mgo_attendance`).
NFC needs a **physical Android phone**; the Android emulator has no NFC.

### Against the local emulators (no Firebase project needed)

1. Start the backend: `npm run emulators`, then `npm run seed`.
2. Connect the phone by USB with USB debugging on, then forward the emulator
   ports to it so `127.0.0.1` on the phone reaches your computer:

   ```bash
   npm run adb:reverse
   ```

3. Run the app:

   ```bash
   cd app
   flutter run --dart-define=USE_EMULATORS=true --dart-define=EMULATOR_HOST=127.0.0.1
   ```

   On the Android emulator (no NFC, but fine for login and admin screens) omit
   `EMULATOR_HOST`; it defaults to `10.0.2.2`, the emulator's alias for your computer.

The app shows an **EMULATOR** ribbon in this mode. Debug builds allow plain HTTP
for the emulators; release builds are HTTPS-only.

### Employee features

- **Check in / out:** open the app and hold the phone near the entrance tag. On
  Android the app listens while it is on screen; it reads the tag UID and URL and
  calls `recordAttendance`, which decides in vs out. Holding the phone on the tag
  doesn't send repeats (3 s cooldown in the app, 2 min on the server).
- **Today card** and **My history** (grouped by day, with first in, last out,
  hours worked and late badge) update live from Firestore.
- Tapping an office tag while the app is closed opens the app (Android intent
  filter for `https://<tagHost>/tag/…`) instead of the browser; tap again once it
  is open. Set `tagHost` in `app/android/gradle.properties` to the tag domain.

### Admin features

Admins land on the admin menu (and can also check in/out themselves):

- **Today:** present / late / absent / in-office counts and the people in each,
  live, for today or any past day. Absent uses the same rules as the payroll
  export: work days only, active people with *Track attendance* on, from their
  start date.
- **Employees:** search, add, edit, deactivate/reactivate, reset password,
  change role, and switch *Track attendance* off for owners or remote staff
  (never counted absent; their taps are still recorded).
- **Tags:** list, rename, disable/enable, and **Add tag / Rewrite or replace**:
  fill in label (the tag ID is generated from it), hold a blank NTAG213/215/216
  sticker to the phone and keep it there. The app reads the UID, calls
  `registerTag`, writes the returned URL and, by default, **locks** the tag.
  If writing is interrupted, tap again: registration is safe to repeat.
- **Export:** semi-monthly payroll presets (1–15, 16–end, this and last month)
  or a custom range; *Daily (payroll)* or *Every tap*; the CSV opens the share
  sheet (Drive, email, …).
- **Settings:** tag domain, late time, time zone, repeat-tap window, work days.

#### Tag locking

Locking uses the NTAG password feature: pages from 4 onwards (the URL) can only
be changed after authenticating; reading stays open, so phones still read the
URL and UID. The 4-byte password is derived per tag from a **tag passphrase**
the admin types when writing (SHA-256 of passphrase + UID), so:

- nothing secret is stored in the app, Firestore or this repo;
- use one passphrase for all office tags and keep it safe — it is needed to
  rewrite a locked tag (a forgotten passphrase means replacing the sticker);
- a password sniffed from one tag does not unlock the others.

NTAG passwords are a deterrent against casual rewriting, not strong crypto; the
server-side UID check and the cloned-tag warning in the logs remain the main
controls. Tags are not permanently locked, so they can be reused.

### Testing with a real tag

1. Start the emulators, `npm run seed`, run the app (see above) and sign in as
   `admin@example.com`.
2. **Tags → Add tag**, label e.g. "Test door", passphrase of 8+ characters,
   **Write tag**, and hold a blank NTAG215 to the back of the phone until it
   says *Tag ready*.
3. Sign out, sign in as `juan@example.com` and tap the tag: first tap checks
   in, a tap within 2 minutes is refused, a later tap checks out. Check
   **Today** as the admin.

The seeded tag domain is `attendance.example.com`, which matches the default
`tagHost` in `app/android/gradle.properties`.

### Against a real Firebase project

Put `google-services.json` (Firebase console → Project settings → Android app
`org.mgocandoniaccounting.mgo_attendance`) in `app/android/app/`, then
`flutter run`. The file is git-ignored; the Gradle build only applies the
Google Services plugin when it is present.

### App tests

```bash
cd app
flutter analyze
flutter test
```

Widget and unit tests use in-memory fakes for Auth and Firestore, so they need
no emulator or device.

## Tests

All backend tests run against the emulators, which `emulators:exec` starts and
stops automatically:

```bash
npm test             # everything (Auth + Firestore emulators)
npm run test:rules   # Firestore security rules only
```

`npm test` builds the functions first. Test layout in `functions/test/`:

| Folder | What | Needs emulator |
|---|---|---|
| `unit/` | pure helpers (time zone, tag UID/URL parsing, CSV) | no |
| `rules/` | Firestore security rules | Firestore |
| `functions/` | function logic against Firestore/Auth, plus end-to-end tests with real ID tokens through the Functions emulator | all |

## Continuous integration

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`:

| Job | Steps |
|---|---|
| **Rules + Cloud Functions** | `npm ci`, typecheck, `npm test` (unit, security rules, functions and end-to-end tests on the Auth/Firestore/Functions emulators) |
| **Flutter app** | `dart format` check, `flutter analyze`, `flutter test`, web build |

CI needs no secrets: everything runs against the emulators under the
`demo-mgo-nfc` project, and the workflow only has read access to the repo.
Deploying to Firebase is a manual step (see below) so production changes
are always deliberate.

## Cloud Functions

### `recordAttendance` (callable)

Request: `{ tagUid: "04A1B2C3D4E5F6", tagUrl: "https://<domain>/tag/<tagId>" }`
(UID separators/case are ignored).

Success: `{ recordId, type: "in" | "out", timestamp, date, late, tagId, tagLabel }`

Rules, all checked in one Firestore transaction:

- caller must be signed in, have a `users/{uid}` doc and be `active`
- the URL must be `https://<host>/tag/<tagId>`; if `settings.tagUrlBase` is set, the host must match
- `tags/{tagId}` must exist, be `active`, and its `uid` must equal the scanned UID
- a tap within `duplicateWindowSeconds` (default 120) of the user's previous tap that
  day is rejected
- type is `out` if the user's last tap that day was `in`, otherwise `in`
- the day's first check-in is `late` if the office-local time is after `lateTime`,
  compared to the minute (with 08:00, 08:00:59 is on time and 08:01 is late);
  taps on days not in `workDays` are never late
- "that day" is the calendar day in `settings.timezone`

The timestamp comes from the Cloud Functions server clock, never from the phone.

Errors are `HttpsError`s with `details.reason` for the app to show a friendly message:

| reason | code |
|---|---|
| `UNAUTHENTICATED` | unauthenticated |
| `INVALID_INPUT`, `INVALID_TAG_URL` | invalid-argument |
| `USER_NOT_FOUND`, `USER_INACTIVE`, `TAG_UID_MISMATCH` | permission-denied |
| `TAG_NOT_REGISTERED` | not-found |
| `TAG_INACTIVE` | failed-precondition |
| `DUPLICATE_TAP` (+ `retryAfterSeconds`, `lastType`) | failed-precondition |

UID mismatches are logged as warnings because they may indicate a cloned tag.

### Admin functions (callable)

All require the caller to have the `admin` claim **and** an active `users` doc
with `role: "admin"`, so a demoted admin loses access immediately. Failures use
`details.reason` as above (`NOT_ADMIN`, `INVALID_INPUT` with `details.issues`, …).

| Function | Input | Result / notes |
|---|---|---|
| `createEmployee` | `email, password (≥8), displayName, employeeId, role?, trackAttendance?` | `{ uid }`. Creates the Auth account, `admin` claim and `users` doc. `EMAIL_EXISTS`, `EMPLOYEE_ID_EXISTS` |
| `updateEmployee` | `uid` + any of `displayName, employeeId, role, active, trackAttendance, password` | `{ uid }`. Deactivating disables sign-in; role change, deactivation or password reset signs the user out everywhere. Admins can't demote/deactivate themselves (`SELF_LOCKOUT`) |
| `registerTag` | `tagId, tagUid, label, location?, replace?` | `{ tagId, tagUid, url, created }`. The app writes `url` to the tag. Safe to call again for the same tag. One physical tag can't have two IDs (`TAG_UID_TAKEN`); reusing an ID for a new tag needs `replace: true` (`TAG_ID_TAKEN`). Needs `settings.tagUrlBase` (`TAG_URL_BASE_NOT_SET`) |
| `exportAttendanceCsv` | `from, to` (YYYY-MM-DD, ≤ 366 days), `format?: "daily" \| "raw"` | `{ filename, csv, rowCount }` |

**Daily CSV** (for payroll): one row per employee per day with Status
`Present` / `Late` / `Absent`, First In, Last Out, Hours Worked (sum of in→out
pairs, so lunch check-outs are excluded), Taps and Notes (`Missing check-out`).
An employee is counted absent on a work day with no taps, only if
`trackAttendance` is on, between their `createdAt` and `deactivatedAt` dates and
not after today. Work on non-work days
still appears. **Raw CSV** lists every tap. Times are in `settings.timezone`. Files
are UTF-8 with BOM so Excel shows names like "María" correctly, and cells that
start with `= + - @` are prefixed with `'` to block formula injection.

Employees are deactivated, never deleted, so their attendance history stays intact.

## Security rules summary

| Collection | Employee | Admin | Client writes |
|---|---|---|---|
| `users` | own doc | all | none (Cloud Functions only) |
| `tags` | read | read; edit `label`/`location`/`active` | create/delete via `registerTag` only |
| `attendance`, `attendanceDays` | own records | all | none (Cloud Functions only) |
| `settings/app` | read | read + validated write | admin only |

Admin status comes from the custom auth claim `admin: true`, set by Cloud
Functions when an admin changes a user's role.

## Connecting to a real Firebase project

1. Create a Firebase project, enable **Authentication → Email/Password** and
   **Firestore** (pick a location near the office, e.g. `asia-southeast1`).
2. `cp .firebaserc.example .firebaserc` and set your project ID.
3. Add an Android app with package `org.mgocandoniaccounting.mgo_attendance`
   and download its `google-services.json` to `app/android/app/`.
4. Deploy: `npx firebase deploy --only firestore,functions`.
5. Create the first admin (the admin functions need an existing admin):

   ```bash
   gcloud auth application-default login
   npm run bootstrap-admin -- --project <project-id> --email you@company.com \
     --name "Your Name" --employee-id ADM-001
   ```

   A new account is created without a password; the script prints a single-use
   password-reset link instead. An existing account is promoted to admin.
6. Sign in to the app as that admin and, under **Settings**, set the tag
   domain, late time and time zone. Set the same domain as `tagHost` in
   `app/android/gradle.properties` and rebuild, so tapping a tag with the app
   closed opens the app.
7. Write and lock the entrance tags under **Tags → Add tag**.

## Secrets

Never commit Firebase config or credentials. The following are git-ignored:
`.firebaserc`, `google-services.json`, `GoogleService-Info.plist`,
`app/lib/firebase_options.dart`, `.env*`, service-account keys, keystores and
`key.properties`. If one is committed by mistake, rotate it — removing it from
git history is not enough.
