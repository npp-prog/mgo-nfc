import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";

initializeApp();

// Asia-southeast1 (Singapore) is the closest region to the office.
setGlobalOptions({ region: "asia-southeast1", maxInstances: 10 });

export { recordAttendance } from "./attendance/recordAttendance";
