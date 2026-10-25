import { Firestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { isValidTimeZone, parseHHMM } from "./time";

export interface AppSettings {
  lateTime: string;
  timezone: string;
  duplicateWindowSeconds: number;
  /** e.g. "https://attendance.example.com/tag/"; empty = accept any https host. */
  tagUrlBase: string;
  workDays: number[];
}

export const DEFAULT_SETTINGS: AppSettings = {
  lateTime: "08:00",
  timezone: "Asia/Manila",
  duplicateWindowSeconds: 120,
  tagUrlBase: "",
  workDays: [1, 2, 3, 4, 5],
};

/** Loads settings/app, falling back to defaults for missing or invalid fields. */
export async function getSettings(db: Firestore): Promise<AppSettings> {
  const snap = await db.doc("settings/app").get();
  const data = (snap.data() ?? {}) as Partial<AppSettings>;
  const s: AppSettings = { ...DEFAULT_SETTINGS, ...data };

  try {
    parseHHMM(s.lateTime);
  } catch {
    logger.warn("Invalid settings.lateTime, using default", { lateTime: s.lateTime });
    s.lateTime = DEFAULT_SETTINGS.lateTime;
  }
  if (typeof s.timezone !== "string" || !isValidTimeZone(s.timezone)) {
    logger.warn("Invalid settings.timezone, using default", { timezone: s.timezone });
    s.timezone = DEFAULT_SETTINGS.timezone;
  }
  if (!Number.isInteger(s.duplicateWindowSeconds) || s.duplicateWindowSeconds < 0) {
    s.duplicateWindowSeconds = DEFAULT_SETTINGS.duplicateWindowSeconds;
  }
  return s;
}
