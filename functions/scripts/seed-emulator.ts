/**
 * Seeds the local emulators with demo users, tags, settings and two weeks of
 * attendance created through the real recordAttendance logic.
 *
 *   npm run emulators   # in one terminal
 *   npm run seed        # in another (from the repo root)
 *
 * Refuses to run against anything but the emulators.
 */
const PROJECT_ID = process.env.GCLOUD_PROJECT ?? "demo-mgo-nfc";
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
if (!PROJECT_ID.startsWith("demo-")) {
  console.error(`Refusing to seed non-demo project "${PROJECT_ID}".`);
  process.exit(1);
}

import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { createEmployeeCore } from "../src/admin/employees";
import { registerTagCore } from "../src/admin/tags";
import { recordTap } from "../src/attendance/recordAttendance";
import { datesBetween, isoWeekdayOf, toLocalTime } from "../src/lib/time";

initializeApp({ projectId: PROJECT_ID });
const auth = getAuth();
const db = getFirestore();

const TZ = "Asia/Manila";
const TAG_BASE = "https://attendance.example.com/tag/";

const people = [
  // The office admin doesn't tap in, so they are never counted absent.
  { email: "admin@example.com", password: "admin1234", displayName: "Office Admin", employeeId: "ADM-001", role: "admin", trackAttendance: false },
  { email: "juan@example.com", password: "password123", displayName: "Juan dela Cruz", employeeId: "EMP-001", role: "employee", trackAttendance: true },
  { email: "maria@example.com", password: "password123", displayName: "María Santos", employeeId: "EMP-002", role: "employee", trackAttendance: true },
  { email: "pedro@example.com", password: "password123", displayName: "Pedro Reyes", employeeId: "EMP-003", role: "employee", trackAttendance: true },
] as const;

const tags = [
  { tagId: "main-entrance", tagUid: "04A1B2C3D4E5F6", label: "Main entrance", location: "Ground floor lobby" },
  { tagId: "back-door", tagUid: "04112233445566", label: "Back door", location: "Parking side" },
];

/** Deterministic pseudo-random so every seed produces the same data. */
let seed = 42;
const rand = () => ((seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31);
const at = (date: string, hh: number, mm: number) =>
  new Date(`${date}T${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}:00+08:00`);

async function main() {
  const existing = await db.collection("users").limit(1).get();
  if (!existing.empty) {
    console.error("Emulator already has users. Restart the emulators (without --import) to reseed.");
    process.exit(1);
  }

  await db.doc("settings/app").set({
    lateTime: "08:00",
    timezone: TZ,
    duplicateWindowSeconds: 120,
    tagUrlBase: TAG_BASE,
    workDays: [1, 2, 3, 4, 5],
  });

  const today = toLocalTime(new Date(), TZ).date;
  const start = new Date(`${today}T00:00:00Z`);
  start.setUTCDate(start.getUTCDate() - 14);
  const from = start.toISOString().slice(0, 10);

  const uids: Record<string, string> = {};
  for (const p of people) {
    const { uid } = await createEmployeeCore(auth, db, null, p);
    // Backdate so the history below is not reported as "before hire".
    await db.doc(`users/${uid}`).update({ createdAt: Timestamp.fromDate(at(from, 0, 0)) });
    uids[p.email] = uid;
  }
  for (const t of tags) await registerTagCore(db, "seed", t);

  const history = datesBetween(from, today).slice(0, -1).filter((d) => isoWeekdayOf(d) <= 5);
  let taps = 0;
  for (const date of history) {
    for (const p of people.slice(1)) {
      if (p.email === "pedro@example.com" && rand() < 0.3) continue; // occasionally absent
      const lateBias = p.email === "maria@example.com" ? 20 : 0;
      const inMin = 7 * 60 + 30 + Math.floor(rand() * 40) + lateBias;
      const outMin = 17 * 60 + Math.floor(rand() * 60);
      const tag = rand() < 0.8 ? tags[0] : tags[1];
      const input = { tagUid: tag.tagUid, tagUrl: TAG_BASE + tag.tagId };
      await recordTap(db, uids[p.email], input, at(date, Math.floor(inMin / 60), inMin % 60));
      // Juan sometimes forgets to check out.
      if (p.email === "juan@example.com" && rand() < 0.15) {
        taps += 1;
        continue;
      }
      await recordTap(db, uids[p.email], input, at(date, Math.floor(outMin / 60), outMin % 60));
      taps += 2;
    }
  }

  console.log(`Seeded ${people.length} users, ${tags.length} tags, ${taps} taps (${history[0]} .. ${history.at(-1)}).`);
  console.log("Sign in with:");
  for (const p of people) console.log(`  ${p.role.padEnd(8)} ${p.email} / ${p.password}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
