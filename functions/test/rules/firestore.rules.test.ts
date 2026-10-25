/**
 * Firestore security rules tests. Run against the Firestore emulator:
 *   npm run test:rules   (from repo root; starts the emulator automatically)
 */
import { readFileSync } from "fs";
import { resolve } from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  setLogLevel,
  updateDoc,
  where,
} from "firebase/firestore";

const PROJECT_ID = "demo-mgo-nfc";

let env: RulesTestEnvironment;

const validSettings = {
  lateTime: "08:00",
  timezone: "Asia/Manila",
  duplicateWindowSeconds: 120,
  tagUrlBase: "https://example.com/tag/",
  workDays: [1, 2, 3, 4, 5],
};

const tag = {
  uid: "04A1B2C3D4E5F6",
  label: "Main entrance",
  location: "Ground floor",
  active: true,
  url: "https://example.com/tag/main",
};

const employee = () => env.authenticatedContext("alice").firestore();
const otherEmployee = () => env.authenticatedContext("bob").firestore();
const admin = () => env.authenticatedContext("boss", { admin: true }).firestore();
const anon = () => env.unauthenticatedContext().firestore();

beforeAll(async () => {
  setLogLevel("error"); // denied writes are expected; keep output readable
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: readFileSync(resolve(__dirname, "../../../firestore.rules"), "utf8") },
  });
});

afterAll(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/alice"), { email: "alice@example.com", role: "employee", active: true });
    await setDoc(doc(db, "users/bob"), { email: "bob@example.com", role: "employee", active: true });
    await setDoc(doc(db, "tags/main"), tag);
    await setDoc(doc(db, "attendance/a1"), { userId: "alice", type: "in", date: "2026-10-26" });
    await setDoc(doc(db, "attendance/b1"), { userId: "bob", type: "in", date: "2026-10-26" });
    await setDoc(doc(db, "attendanceDays/alice_2026-10-26"), { userId: "alice", date: "2026-10-26" });
    await setDoc(doc(db, "settings/app"), validSettings);
  });
});

describe("users", () => {
  test("employee reads own user doc", async () => {
    await assertSucceeds(getDoc(doc(employee(), "users/alice")));
  });
  test("employee cannot read another user doc", async () => {
    await assertFails(getDoc(doc(employee(), "users/bob")));
  });
  test("employee cannot list users", async () => {
    await assertFails(getDocs(collection(employee(), "users")));
  });
  test("admin reads and lists all users", async () => {
    await assertSucceeds(getDoc(doc(admin(), "users/bob")));
    await assertSucceeds(getDocs(collection(admin(), "users")));
  });
  test("employee cannot promote themselves", async () => {
    await assertFails(updateDoc(doc(employee(), "users/alice"), { role: "admin" }));
  });
  test("admin cannot write user docs directly (must use functions)", async () => {
    await assertFails(setDoc(doc(admin(), "users/carol"), { role: "employee" }));
  });
  test("unauthenticated cannot read", async () => {
    await assertFails(getDoc(doc(anon(), "users/alice")));
  });
});

describe("tags", () => {
  test("signed-in user reads tags", async () => {
    await assertSucceeds(getDoc(doc(employee(), "tags/main")));
  });
  test("unauthenticated cannot read tags", async () => {
    await assertFails(getDoc(doc(anon(), "tags/main")));
  });
  test("employee cannot modify tags", async () => {
    await assertFails(updateDoc(doc(employee(), "tags/main"), { active: false }));
    await assertFails(setDoc(doc(employee(), "tags/fake"), tag));
  });
  test("admin can update label/location/active", async () => {
    await assertSucceeds(updateDoc(doc(admin(), "tags/main"), { label: "Front door", active: false }));
  });
  test("admin cannot change a tag UID directly", async () => {
    await assertFails(updateDoc(doc(admin(), "tags/main"), { uid: "04FFFFFFFFFFFF" }));
  });
  test("admin cannot create or delete tags directly (must use registerTag)", async () => {
    await assertFails(setDoc(doc(admin(), "tags/new"), tag));
    await assertFails(deleteDoc(doc(admin(), "tags/main")));
  });
});

describe("attendance", () => {
  test("employee reads own record", async () => {
    await assertSucceeds(getDoc(doc(employee(), "attendance/a1")));
  });
  test("employee cannot read another's record", async () => {
    await assertFails(getDoc(doc(employee(), "attendance/b1")));
  });
  test("employee can query own records only", async () => {
    const db = employee();
    await assertSucceeds(getDocs(query(collection(db, "attendance"), where("userId", "==", "alice"))));
    await assertFails(getDocs(collection(db, "attendance")));
    await assertFails(getDocs(query(collection(db, "attendance"), where("userId", "==", "bob"))));
  });
  test("nobody writes attendance from the client", async () => {
    const rec = { userId: "alice", type: "in", date: "2026-10-26" };
    await assertFails(setDoc(doc(employee(), "attendance/x"), rec));
    await assertFails(updateDoc(doc(employee(), "attendance/a1"), { type: "out" }));
    await assertFails(deleteDoc(doc(employee(), "attendance/a1")));
    await assertFails(setDoc(doc(admin(), "attendance/x"), rec));
    await assertFails(deleteDoc(doc(admin(), "attendance/b1")));
  });
  test("admin reads all records", async () => {
    await assertSucceeds(getDocs(collection(admin(), "attendance")));
  });
});

describe("attendanceDays", () => {
  test("employee reads own summary but not others", async () => {
    await assertSucceeds(getDoc(doc(employee(), "attendanceDays/alice_2026-10-26")));
    await assertFails(getDoc(doc(otherEmployee(), "attendanceDays/alice_2026-10-26")));
  });
  test("no client writes", async () => {
    await assertFails(setDoc(doc(employee(), "attendanceDays/alice_2026-10-27"), { userId: "alice" }));
    await assertFails(setDoc(doc(admin(), "attendanceDays/alice_2026-10-27"), { userId: "alice" }));
  });
  test("admin reads all summaries", async () => {
    await assertSucceeds(getDocs(collection(admin(), "attendanceDays")));
  });
});

describe("settings", () => {
  test("signed-in user reads settings", async () => {
    await assertSucceeds(getDoc(doc(employee(), "settings/app")));
  });
  test("employee cannot change settings", async () => {
    await assertFails(setDoc(doc(employee(), "settings/app"), { ...validSettings, lateTime: "09:00" }));
  });
  test("admin can change settings with valid values", async () => {
    await assertSucceeds(setDoc(doc(admin(), "settings/app"), { ...validSettings, lateTime: "08:30" }));
  });
  test.each([
    ["bad lateTime", { lateTime: "8am" }],
    ["out-of-range lateTime", { lateTime: "24:00" }],
    ["non-int window", { duplicateWindowSeconds: 1.5 }],
    ["too-long window", { duplicateWindowSeconds: 99999 }],
    ["non-https url", { tagUrlBase: "http://example.com/tag/" }],
    ["invalid weekday", { workDays: [0, 1] }],
    ["unknown field", { extra: true }],
  ])("admin cannot save invalid settings: %s", async (_name, patch) => {
    await assertFails(setDoc(doc(admin(), "settings/app"), { ...validSettings, ...patch }));
  });
  test("admin can save settings before the tag domain is decided", async () => {
    await assertSucceeds(setDoc(doc(admin(), "settings/app"), { ...validSettings, tagUrlBase: "" }));
  });
  test("admin cannot write other settings docs", async () => {
    await assertFails(setDoc(doc(admin(), "settings/other"), validSettings));
  });
});

describe("unknown collections", () => {
  test("are denied", async () => {
    await assertFails(getDoc(doc(admin(), "secrets/x")));
    await assertFails(setDoc(doc(admin(), "secrets/x"), { a: 1 }));
  });
});
