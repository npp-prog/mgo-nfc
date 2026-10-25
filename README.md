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

Quick check that functions are wired up:

```bash
curl -X POST -H 'Content-Type: application/json' -d '{"data":{}}' \
  http://127.0.0.1:5001/demo-mgo-nfc/asia-southeast1/ping
# {"result":{"ok":true,"uid":null}}
```

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
