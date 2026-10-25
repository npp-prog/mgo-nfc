/**
 * End-to-end: real client SDK -> Auth emulator -> Functions emulator -> Firestore emulator.
 * Proves the deployed callable enforces authentication and writes with the server clock.
 */
import { deleteApp, FirebaseApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, createUserWithEmailAndPassword, getAuth, signOut } from "firebase/auth";
import { connectFunctionsEmulator, FunctionsError, getFunctions, httpsCallable } from "firebase/functions";
import { adminDb, clearAuth, clearFirestore, PROJECT_ID } from "../helpers/emulator";

const UID = "04A1B2C3D4E5F6";

let app: FirebaseApp;

beforeAll(() => {
  if (!process.env.FUNCTIONS_EMULATOR_HOST && !process.env.FIREBASE_EMULATOR_HUB) {
    throw new Error("Functions emulator not running; use `npm test` from the repo root.");
  }
  app = initializeApp({ projectId: PROJECT_ID, apiKey: "fake-api-key" }, "e2e");
  connectAuthEmulator(getAuth(app), `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`, { disableWarnings: true });
  connectFunctionsEmulator(getFunctions(app, "asia-southeast1"), "127.0.0.1", 5001);
});

afterAll(async () => {
  await deleteApp(app);
});

beforeEach(async () => {
  await Promise.all([clearFirestore(), clearAuth()]);
  await adminDb().doc("tags/main").set({ uid: UID, label: "Main entrance", active: true });
});

const call = (data: unknown) => httpsCallable(getFunctions(app, "asia-southeast1"), "recordAttendance")(data);

test("rejects unauthenticated callers", async () => {
  await signOut(getAuth(app));
  await expect(call({ tagUid: UID, tagUrl: "https://att.example.com/tag/main" })).rejects.toMatchObject({
    code: "functions/unauthenticated",
  });
});

test("signed-in employee checks in, then a quick repeat tap is rejected", async () => {
  const cred = await createUserWithEmailAndPassword(getAuth(app), "alice@example.com", "password123");
  await adminDb().doc(`users/${cred.user.uid}`).set({ email: "alice@example.com", role: "employee", active: true });

  const before = Date.now();
  const res = await call({ tagUid: UID, tagUrl: "https://att.example.com/tag/main" });
  const data = res.data as { type: string; timestamp: string };
  expect(data.type).toBe("in");
  const ts = Date.parse(data.timestamp);
  expect(ts).toBeGreaterThanOrEqual(before - 5000);
  expect(ts).toBeLessThanOrEqual(Date.now() + 5000);

  const err = (await call({ tagUid: UID, tagUrl: "https://att.example.com/tag/main" }).catch((e) => e)) as FunctionsError;
  expect(err.code).toBe("functions/failed-precondition");
  expect(err.details).toMatchObject({ reason: "DUPLICATE_TAP" });

  const recs = await adminDb().collection("attendance").where("userId", "==", cred.user.uid).get();
  expect(recs.size).toBe(1);
});
