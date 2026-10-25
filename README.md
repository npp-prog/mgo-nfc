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
- Flutter SDK (stable) + Android Studio / Android SDK
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
| `unit/` | pure helpers (time zone, tag UID/URL parsing) | no |
| `rules/` | Firestore security rules | Firestore |
| `functions/` | function logic against Firestore, plus an end-to-end test through Auth + Functions | all |

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
  compared to the minute (with 08:00, 08:00:59 is on time and 08:01 is late)
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
3. In `app/`, run `flutterfire configure` — this generates
   `lib/firebase_options.dart` and `android/app/google-services.json`.
4. Deploy: `npx firebase deploy --only firestore,functions`.

## Secrets

Never commit Firebase config or credentials. The following are git-ignored:
`.firebaserc`, `google-services.json`, `GoogleService-Info.plist`,
`app/lib/firebase_options.dart`, `.env*`, service-account keys, keystores and
`key.properties`. If one is committed by mistake, rotate it — removing it from
git history is not enough.
