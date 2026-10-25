/**
 * Creates or promotes the first admin in a REAL Firebase project (the admin
 * functions require an existing admin, so the first one must be made here).
 *
 *   gcloud auth application-default login
 *   npm run bootstrap-admin -- --project <id> --email you@company.com --name "Your Name" --employee-id ADM-001
 *
 * A new account gets no password; the script prints a one-time password-reset
 * link instead, so no password ever passes through the terminal or shell history.
 */
import { initializeApp } from "firebase-admin/app";
import { getAuth, UserRecord } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { parseArgs } from "node:util";

const { values } = parseArgs({
  options: {
    project: { type: "string" },
    email: { type: "string" },
    name: { type: "string" },
    "employee-id": { type: "string" },
  },
});
const projectId = values.project ?? process.env.GCLOUD_PROJECT;
const email = values.email?.trim().toLowerCase();
const name = values.name?.trim();
const employeeId = values["employee-id"]?.trim();
if (!projectId || !email || !name || !employeeId) {
  console.error("Usage: npm run bootstrap-admin -- --project <id> --email <email> --name <name> --employee-id <id>");
  process.exit(1);
}

initializeApp({ projectId });
const auth = getAuth();
const db = getFirestore();

async function main() {
  const clash = await db.collection("users").where("employeeId", "==", employeeId).get();

  let user: UserRecord;
  let created = false;
  try {
    user = await auth.getUserByEmail(email!);
  } catch (e) {
    if ((e as { code?: string }).code !== "auth/user-not-found") throw e;
    user = await auth.createUser({ email, displayName: name });
    created = true;
  }
  if (clash.docs.some((d) => d.id !== user.uid)) {
    console.error(`Employee ID ${employeeId} is already used by another user.`);
    process.exit(1);
  }

  await auth.setCustomUserClaims(user.uid, { ...(user.customClaims ?? {}), admin: true });
  const ref = db.doc(`users/${user.uid}`);
  const snap = await ref.get();
  await ref.set(
    {
      email,
      displayName: name,
      employeeId,
      role: "admin",
      active: true,
      updatedAt: FieldValue.serverTimestamp(),
      ...(snap.exists ? {} : { createdAt: FieldValue.serverTimestamp(), createdBy: "bootstrap" }),
    },
    { merge: true },
  );
  await auth.revokeRefreshTokens(user.uid);

  console.log(`${created ? "Created" : "Promoted"} admin ${email} (uid ${user.uid}) in project ${projectId}.`);
  if (created) {
    console.log("Open this link to set the password (single use):");
    console.log(await auth.generatePasswordResetLink(email!));
  } else {
    console.log("Sign out and back in to the app to pick up admin access.");
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
