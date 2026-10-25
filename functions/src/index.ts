import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";
import { onCall } from "firebase-functions/v2/https";

initializeApp();

// Asia-southeast1 (Singapore) is the closest region to the office.
setGlobalOptions({ region: "asia-southeast1", maxInstances: 10 });

/** Smoke-test endpoint used to verify the emulator/deploy wiring. */
export const ping = onCall((request) => ({
  ok: true,
  uid: request.auth?.uid ?? null,
}));
