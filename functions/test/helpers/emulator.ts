import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

export const PROJECT_ID = "demo-mgo-nfc";

/** Admin SDK bound to the Firestore emulator (FIRESTORE_EMULATOR_HOST is set by emulators:exec). */
export function adminDb() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("FIRESTORE_EMULATOR_HOST not set; run tests via `npm test` from the repo root.");
  }
  if (!getApps().length) initializeApp({ projectId: PROJECT_ID });
  return getFirestore();
}

export async function clearFirestore() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const res = await fetch(
    `http://${host}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`,
    { method: "DELETE" },
  );
  if (!res.ok) throw new Error(`Failed to clear Firestore emulator: ${res.status}`);
}

export async function clearAuth() {
  const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const res = await fetch(`http://${host}/emulator/v1/projects/${PROJECT_ID}/accounts`, { method: "DELETE" });
  if (!res.ok) throw new Error(`Failed to clear Auth emulator: ${res.status}`);
}

/** Manila is UTC+8 with no DST: builds an instant from Manila wall-clock time. */
export function manila(date: string, time: string): Date {
  return new Date(`${date}T${time}+08:00`);
}
