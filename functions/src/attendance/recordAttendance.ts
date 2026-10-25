import { Firestore, Timestamp } from "firebase-admin/firestore";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { onCall } from "firebase-functions/v2/https";
import { fail } from "../lib/errors";
import { getSettings } from "../lib/settings";
import { normalizeTagUid, parseTagUrl } from "../lib/tags";
import { parseHHMM, toLocalTime } from "../lib/time";

export interface RecordAttendanceInput {
  /** Tag UID as read by the phone; separators and case are ignored. */
  tagUid: string;
  /** NDEF URL stored on the tag: https://<domain>/tag/<tagId>. */
  tagUrl: string;
}

export interface RecordAttendanceResult {
  recordId: string;
  type: "in" | "out";
  timestamp: string;
  date: string;
  late: boolean;
  tagId: string;
  tagLabel: string;
}

/**
 * Validates a tap and writes the attendance record + day summary atomically.
 * `now` is the server clock (Cloud Functions host); clients cannot influence it.
 */
export async function recordTap(
  db: Firestore,
  userId: string,
  input: Partial<RecordAttendanceInput> | undefined,
  now: Date = new Date(),
): Promise<RecordAttendanceResult> {
  const settings = await getSettings(db);

  const tagUid = normalizeTagUid(input?.tagUid);
  if (!tagUid) fail("invalid-argument", "INVALID_INPUT", "Missing or malformed tag UID.");
  const tagId = parseTagUrl(input?.tagUrl, settings.tagUrlBase);
  if (!tagId) fail("invalid-argument", "INVALID_TAG_URL", "This tag is not an office attendance tag.");

  const local = toLocalTime(now, settings.timezone);
  const nowTs = Timestamp.fromDate(now);
  const userRef = db.doc(`users/${userId}`);
  const tagRef = db.doc(`tags/${tagId}`);
  const dayRef = db.doc(`attendanceDays/${userId}_${local.date}`);
  const recordRef = db.collection("attendance").doc();

  return db.runTransaction(async (tx) => {
    const [userSnap, tagSnap, daySnap] = await tx.getAll(userRef, tagRef, dayRef);

    if (!userSnap.exists) fail("permission-denied", "USER_NOT_FOUND", "Your account is not set up for attendance.");
    const user = userSnap.data()!;
    if (user.active !== true) fail("permission-denied", "USER_INACTIVE", "Your account is deactivated.");

    if (!tagSnap.exists) fail("not-found", "TAG_NOT_REGISTERED", "This tag is not registered.");
    const tag = tagSnap.data()!;
    if (tag.active !== true) fail("failed-precondition", "TAG_INACTIVE", "This tag has been deactivated.");
    if (tag.uid !== tagUid) {
      logger.warn("Tag UID mismatch (possible cloned tag)", { userId, tagId, scannedUid: tagUid });
      fail("permission-denied", "TAG_UID_MISMATCH", "This tag could not be verified.");
    }

    const day = daySnap.exists ? daySnap.data()! : undefined;
    const lastTapAt = day?.lastTapAt as Timestamp | undefined;
    if (lastTapAt) {
      const elapsed = (now.getTime() - lastTapAt.toMillis()) / 1000;
      if (elapsed < settings.duplicateWindowSeconds) {
        fail("failed-precondition", "DUPLICATE_TAP", "You already tapped a moment ago.", {
          lastType: day!.lastType,
          retryAfterSeconds: Math.ceil(settings.duplicateWindowSeconds - elapsed),
        });
      }
    }

    const type: "in" | "out" = day?.lastType === "in" ? "out" : "in";
    const isFirstIn = type === "in" && !day?.firstIn;
    // Lateness only applies on scheduled work days (weekend overtime is never late).
    const late =
      isFirstIn && settings.workDays.includes(local.isoWeekday) && local.minutes > parseHHMM(settings.lateTime);
    const userName = (user.displayName as string | undefined) ?? (user.email as string | undefined) ?? "";

    tx.create(recordRef, {
      userId,
      userName,
      tagId,
      tagUid,
      type,
      timestamp: nowTs,
      date: local.date,
      late,
    });

    const daySummary: Record<string, unknown> = {
      userId,
      userName,
      date: local.date,
      lastType: type,
      lastTapAt: nowTs,
      tapCount: (day?.tapCount ?? 0) + 1,
    };
    if (isFirstIn) {
      daySummary.firstIn = nowTs;
      daySummary.late = late;
    }
    if (type === "out") daySummary.lastOut = nowTs;
    tx.set(dayRef, daySummary, { merge: true });

    return {
      recordId: recordRef.id,
      type,
      timestamp: now.toISOString(),
      date: local.date,
      late,
      tagId,
      tagLabel: (tag.label as string | undefined) ?? tagId,
    };
  });
}

export const recordAttendance = onCall<Partial<RecordAttendanceInput>>(async (request) => {
  if (!request.auth) fail("unauthenticated", "UNAUTHENTICATED", "Please sign in first.");
  return recordTap(getFirestore(), request.auth.uid, request.data);
});
