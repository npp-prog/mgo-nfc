import { Auth, UpdateRequest } from "firebase-admin/auth";
import { FieldValue, Firestore } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";
import { z } from "zod";
import { requireAdmin } from "../lib/auth";
import { fail, parseInput } from "../lib/errors";

const role = z.enum(["employee", "admin"]);
const displayName = z.string().trim().min(1).max(100);
const employeeId = z.string().trim().min(1).max(32).regex(/^[A-Za-z0-9_-]+$/, "letters, digits, - and _ only");
const password = z.string().min(8, "must be at least 8 characters").max(128);

export const createEmployeeSchema = z.object({
  email: z.email().max(254).transform((e) => e.toLowerCase()),
  password,
  displayName,
  employeeId,
  role: role.default("employee"),
  /** false = never counted absent (owners, remote staff); taps are still recorded. */
  trackAttendance: z.boolean().default(true),
});
export type CreateEmployeeInput = z.input<typeof createEmployeeSchema>;

export const updateEmployeeSchema = z
  .object({
    uid: z.string().min(1).max(128),
    displayName: displayName.optional(),
    employeeId: employeeId.optional(),
    role: role.optional(),
    active: z.boolean().optional(),
    trackAttendance: z.boolean().optional(),
    password: password.optional(),
  })
  .refine((v) => Object.keys(v).length > 1, "nothing to update");
export type UpdateEmployeeInput = z.input<typeof updateEmployeeSchema>;

async function assertEmployeeIdFree(db: Firestore, id: string, exceptUid?: string) {
  const snap = await db.collection("users").where("employeeId", "==", id).limit(2).get();
  if (snap.docs.some((d) => d.id !== exceptUid)) {
    fail("already-exists", "EMPLOYEE_ID_EXISTS", `Employee ID ${id} is already in use.`);
  }
}

/** Creates the Auth account, role claim and users/{uid} doc. Rolls back the account on failure. */
export async function createEmployeeCore(
  auth: Auth,
  db: Firestore,
  actorUid: string | null,
  rawInput: unknown,
): Promise<{ uid: string }> {
  const input = parseInput(createEmployeeSchema, rawInput);
  await assertEmployeeIdFree(db, input.employeeId);

  let uid: string;
  try {
    ({ uid } = await auth.createUser({
      email: input.email,
      password: input.password,
      displayName: input.displayName,
    }));
  } catch (e) {
    if ((e as { code?: string }).code === "auth/email-already-exists") {
      fail("already-exists", "EMAIL_EXISTS", `${input.email} already has an account.`);
    }
    throw e;
  }

  try {
    await auth.setCustomUserClaims(uid, { admin: input.role === "admin" });
    await db.doc(`users/${uid}`).create({
      email: input.email,
      displayName: input.displayName,
      employeeId: input.employeeId,
      role: input.role,
      active: true,
      trackAttendance: input.trackAttendance,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      createdBy: actorUid,
    });
  } catch (e) {
    await auth.deleteUser(uid).catch(() => undefined);
    throw e;
  }
  return { uid };
}

/**
 * Updates profile, role, active flag or password. Role changes and
 * deactivation revoke refresh tokens so the user must sign in again.
 */
export async function updateEmployeeCore(
  auth: Auth,
  db: Firestore,
  actorUid: string,
  rawInput: unknown,
): Promise<{ uid: string }> {
  const input = parseInput(updateEmployeeSchema, rawInput);
  const ref = db.doc(`users/${input.uid}`);
  const snap = await ref.get();
  if (!snap.exists) fail("not-found", "USER_NOT_FOUND", "Employee not found.");
  const current = snap.data()!;

  if (input.uid === actorUid && (input.role === "employee" || input.active === false)) {
    fail("failed-precondition", "SELF_LOCKOUT", "You cannot demote or deactivate your own account.");
  }
  if (input.employeeId && input.employeeId !== current.employeeId) {
    await assertEmployeeIdFree(db, input.employeeId, input.uid);
  }

  const authUpdate: UpdateRequest = {};
  if (input.displayName !== undefined) authUpdate.displayName = input.displayName;
  if (input.password !== undefined) authUpdate.password = input.password;
  if (input.active !== undefined) authUpdate.disabled = !input.active;
  if (Object.keys(authUpdate).length) await auth.updateUser(input.uid, authUpdate);

  const roleChanged = input.role !== undefined && input.role !== current.role;
  if (roleChanged) await auth.setCustomUserClaims(input.uid, { admin: input.role === "admin" });

  const docUpdate: Record<string, unknown> = { updatedAt: FieldValue.serverTimestamp(), updatedBy: actorUid };
  for (const k of ["displayName", "employeeId", "role", "active", "trackAttendance"] as const) {
    if (input[k] !== undefined) docUpdate[k] = input[k];
  }
  if (input.active === false && current.active !== false) docUpdate.deactivatedAt = FieldValue.serverTimestamp();
  if (input.active === true) docUpdate.deactivatedAt = FieldValue.delete();
  await ref.update(docUpdate);

  if (roleChanged || (input.active === false && current.active !== false) || input.password !== undefined) {
    await auth.revokeRefreshTokens(input.uid);
  }
  return { uid: input.uid };
}

export const createEmployee = onCall(async (request) => {
  const db = getFirestore();
  const actor = await requireAdmin(request, db);
  return createEmployeeCore(getAuth(), db, actor, request.data);
});

export const updateEmployee = onCall(async (request) => {
  const db = getFirestore();
  const actor = await requireAdmin(request, db);
  return updateEmployeeCore(getAuth(), db, actor, request.data);
});
