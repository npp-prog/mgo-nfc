import { Auth, getAuth } from "firebase-admin/auth";
import { Firestore } from "firebase-admin/firestore";
import { createEmployeeCore, updateEmployeeCore } from "../../src/admin/employees";
import { adminDb, clearAuth, clearFirestore } from "../helpers/emulator";
import { expectReason } from "../helpers/errors";

let db: Firestore;
let auth: Auth;

const base = { email: "Alice@Example.com", password: "password123", displayName: "Alice", employeeId: "EMP-001" };

beforeAll(() => {
  db = adminDb();
  auth = getAuth();
});

beforeEach(async () => {
  await Promise.all([clearFirestore(), clearAuth()]);
});

describe("createEmployee", () => {
  test("creates auth user, claim and profile doc", async () => {
    const { uid } = await createEmployeeCore(auth, db, "boss", base);
    const user = await auth.getUser(uid);
    expect(user.email).toBe("alice@example.com");
    expect(user.displayName).toBe("Alice");
    expect(user.customClaims).toEqual({ admin: false });

    const doc = (await db.doc(`users/${uid}`).get()).data()!;
    expect(doc).toMatchObject({
      email: "alice@example.com",
      displayName: "Alice",
      employeeId: "EMP-001",
      role: "employee",
      active: true,
      createdBy: "boss",
    });
    expect(doc.createdAt).toBeDefined();
  });

  test("admin role sets the admin claim", async () => {
    const { uid } = await createEmployeeCore(auth, db, "boss", { ...base, role: "admin" });
    expect((await auth.getUser(uid)).customClaims).toEqual({ admin: true });
  });

  test("rejects duplicate email", async () => {
    await createEmployeeCore(auth, db, "boss", base);
    await expectReason(
      createEmployeeCore(auth, db, "boss", { ...base, employeeId: "EMP-002" }),
      "already-exists",
      "EMAIL_EXISTS",
    );
  });

  test("rejects duplicate employee ID without creating an auth user", async () => {
    await createEmployeeCore(auth, db, "boss", base);
    await expectReason(
      createEmployeeCore(auth, db, "boss", { ...base, email: "bob@example.com" }),
      "already-exists",
      "EMPLOYEE_ID_EXISTS",
    );
    await expect(auth.getUserByEmail("bob@example.com")).rejects.toMatchObject({ code: "auth/user-not-found" });
  });

  test.each([
    ["bad email", { email: "nope" }],
    ["short password", { password: "short" }],
    ["blank name", { displayName: "  " }],
    ["bad employee id", { employeeId: "EMP 1" }],
    ["unknown role", { role: "owner" }],
  ])("rejects %s", async (_n, patch) => {
    const err = await expectReason(
      createEmployeeCore(auth, db, "boss", { ...base, ...patch }),
      "invalid-argument",
      "INVALID_INPUT",
    );
    expect((err.details as { issues: unknown[] }).issues.length).toBeGreaterThan(0);
  });
});

describe("updateEmployee", () => {
  let uid: string;
  beforeEach(async () => {
    ({ uid } = await createEmployeeCore(auth, db, "boss", base));
  });

  test("updates profile fields in auth and Firestore", async () => {
    await updateEmployeeCore(auth, db, "boss", { uid, displayName: "Alice B.", employeeId: "EMP-010" });
    expect((await auth.getUser(uid)).displayName).toBe("Alice B.");
    expect((await db.doc(`users/${uid}`).get()).data()).toMatchObject({
      displayName: "Alice B.",
      employeeId: "EMP-010",
      updatedBy: "boss",
    });
  });

  test("promotion sets claim and revokes sessions", async () => {
    const before = (await auth.getUser(uid)).tokensValidAfterTime;
    await new Promise((r) => setTimeout(r, 1100));
    await updateEmployeeCore(auth, db, "boss", { uid, role: "admin" });
    const user = await auth.getUser(uid);
    expect(user.customClaims).toEqual({ admin: true });
    expect(user.tokensValidAfterTime).not.toBe(before);
    expect((await db.doc(`users/${uid}`).get()).get("role")).toBe("admin");
  });

  test("deactivation disables login and records deactivatedAt; reactivation clears it", async () => {
    await updateEmployeeCore(auth, db, "boss", { uid, active: false });
    expect((await auth.getUser(uid)).disabled).toBe(true);
    let doc = (await db.doc(`users/${uid}`).get()).data()!;
    expect(doc.active).toBe(false);
    expect(doc.deactivatedAt).toBeDefined();

    await updateEmployeeCore(auth, db, "boss", { uid, active: true });
    expect((await auth.getUser(uid)).disabled).toBe(false);
    doc = (await db.doc(`users/${uid}`).get()).data()!;
    expect(doc.active).toBe(true);
    expect(doc.deactivatedAt).toBeUndefined();
  });

  test("admin cannot demote or deactivate themselves", async () => {
    const { uid: bossUid } = await createEmployeeCore(auth, db, null, {
      ...base,
      email: "boss@example.com",
      employeeId: "ADM-1",
      role: "admin",
    });
    await expectReason(
      updateEmployeeCore(auth, db, bossUid, { uid: bossUid, role: "employee" }),
      "failed-precondition",
      "SELF_LOCKOUT",
    );
    await expectReason(
      updateEmployeeCore(auth, db, bossUid, { uid: bossUid, active: false }),
      "failed-precondition",
      "SELF_LOCKOUT",
    );
    // but may edit their own name
    await updateEmployeeCore(auth, db, bossUid, { uid: bossUid, displayName: "The Boss" });
  });

  test("rejects an employee ID used by someone else", async () => {
    await createEmployeeCore(auth, db, "boss", { ...base, email: "bob@example.com", employeeId: "EMP-002" });
    await expectReason(
      updateEmployeeCore(auth, db, "boss", { uid, employeeId: "EMP-002" }),
      "already-exists",
      "EMPLOYEE_ID_EXISTS",
    );
  });

  test("rejects unknown user and empty update", async () => {
    await expectReason(updateEmployeeCore(auth, db, "boss", { uid: "ghost", active: false }), "not-found", "USER_NOT_FOUND");
    await expectReason(updateEmployeeCore(auth, db, "boss", { uid }), "invalid-argument", "INVALID_INPUT");
  });
});
