/**
 * End-to-end role enforcement through the Functions emulator with real ID tokens.
 */
import { deleteApp, FirebaseApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInWithEmailAndPassword, signOut } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import { getAuth as getAdminAuth } from "firebase-admin/auth";
import { createEmployeeCore } from "../../src/admin/employees";
import { adminDb, clearAuth, clearFirestore, PROJECT_ID } from "../helpers/emulator";

let app: FirebaseApp;

beforeAll(() => {
  app = initializeApp({ projectId: PROJECT_ID, apiKey: "fake-api-key" }, "admin-e2e");
  connectAuthEmulator(getAuth(app), `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`, { disableWarnings: true });
  connectFunctionsEmulator(getFunctions(app, "asia-southeast1"), "127.0.0.1", 5001);
});

afterAll(async () => {
  await deleteApp(app);
});

let adminUid: string;

beforeEach(async () => {
  await signOut(getAuth(app));
  await Promise.all([clearFirestore(), clearAuth()]);
  const db = adminDb();
  await db.doc("settings/app").set({ tagUrlBase: "https://att.example.com/tag/" });
  ({ uid: adminUid } = await createEmployeeCore(getAdminAuth(), db, null, {
    email: "boss@example.com",
    password: "password123",
    displayName: "Boss",
    employeeId: "ADM-1",
    role: "admin",
  }));
  await createEmployeeCore(getAdminAuth(), db, null, {
    email: "emp@example.com",
    password: "password123",
    displayName: "Emp",
    employeeId: "EMP-1",
  });
});

const call = (name: string, data: unknown) => httpsCallable(getFunctions(app, "asia-southeast1"), name)(data);
const signIn = (email: string) => signInWithEmailAndPassword(getAuth(app), email, "password123");

const ADMIN_CALLS: [string, unknown][] = [
  ["createEmployee", { email: "x@example.com", password: "password123", displayName: "X", employeeId: "X1" }],
  ["updateEmployee", { uid: "whoever", displayName: "Y" }],
  ["registerTag", { tagId: "t1", tagUid: "04A1B2C3D4E5F6", label: "T1" }],
  ["exportAttendanceCsv", { from: "2026-10-01", to: "2026-10-31" }],
];

test.each(ADMIN_CALLS)("%s rejects signed-out callers", async (name, data) => {
  await expect(call(name, data)).rejects.toMatchObject({ code: "functions/unauthenticated" });
});

test.each(ADMIN_CALLS)("%s rejects employees", async (name, data) => {
  await signIn("emp@example.com");
  await expect(call(name, data)).rejects.toMatchObject({
    code: "functions/permission-denied",
    details: { reason: "NOT_ADMIN" },
  });
});

test("admin can create an employee, register a tag and export", async () => {
  await signIn("boss@example.com");
  const created = (await call("createEmployee", ADMIN_CALLS[0][1])).data as { uid: string };
  expect((await adminDb().doc(`users/${created.uid}`).get()).get("createdBy")).toBe(adminUid);

  const tag = (await call("registerTag", ADMIN_CALLS[2][1])).data as { url: string };
  expect(tag.url).toBe("https://att.example.com/tag/t1");

  const exp = (await call("exportAttendanceCsv", ADMIN_CALLS[3][1])).data as { csv: string };
  expect(exp.csv).toContain("Employee ID");
});

test("a demoted admin is rejected even with a still-valid token carrying the old claim", async () => {
  await signIn("boss@example.com"); // token now has admin: true
  await adminDb().doc(`users/${adminUid}`).update({ role: "employee" });
  await expect(call("registerTag", ADMIN_CALLS[2][1])).rejects.toMatchObject({
    details: { reason: "NOT_ADMIN" },
  });
});
