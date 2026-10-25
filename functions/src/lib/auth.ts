import { Firestore } from "firebase-admin/firestore";
import { CallableRequest } from "firebase-functions/v2/https";
import { fail } from "./errors";

/**
 * Ensures the caller is an active admin. Checks both the `admin` custom claim
 * and the user doc, so a demoted admin is locked out immediately even if their
 * ID token (with the old claim) has not expired yet.
 */
export async function requireAdmin(request: CallableRequest, db: Firestore): Promise<string> {
  if (!request.auth) fail("unauthenticated", "UNAUTHENTICATED", "Please sign in first.");
  const uid = request.auth.uid;
  if (request.auth.token.admin !== true) fail("permission-denied", "NOT_ADMIN", "Admin access required.");
  const snap = await db.doc(`users/${uid}`).get();
  if (snap.get("role") !== "admin" || snap.get("active") !== true) {
    fail("permission-denied", "NOT_ADMIN", "Admin access required.");
  }
  return uid;
}
