import { HttpsError } from "firebase-functions/v2/https";
import { Firestore, Timestamp } from "firebase-admin/firestore";
import { recordTap } from "../../src/attendance/recordAttendance";
import { adminDb, clearFirestore, manila } from "../helpers/emulator";

const UID = "04A1B2C3D4E5F6";
const URL_MAIN = "https://att.example.com/tag/main";
const DAY = "2026-10-26"; // Monday

let db: Firestore;

beforeAll(() => {
  db = adminDb();
});

beforeEach(async () => {
  await clearFirestore();
  await db.doc("users/alice").set({ email: "alice@example.com", displayName: "Alice", role: "employee", active: true });
  await db.doc("users/zed").set({ email: "zed@example.com", role: "employee", active: false });
  await db.doc("tags/main").set({ uid: UID, label: "Main entrance", active: true });
  await db.doc("tags/old").set({ uid: "04FFFFFFFFFFFF", label: "Old door", active: false });
  await db.doc("settings/app").set({
    lateTime: "08:00",
    timezone: "Asia/Manila",
    duplicateWindowSeconds: 120,
    tagUrlBase: "https://att.example.com/tag/",
    workDays: [1, 2, 3, 4, 5],
  });
});

const tap = (at: Date, input: Record<string, unknown> = { tagUid: UID, tagUrl: URL_MAIN }, user = "alice") =>
  recordTap(db, user, input, at);

async function expectReason(p: Promise<unknown>, code: string, reason: string) {
  const err = await p.then(
    () => {
      throw new Error("expected rejection");
    },
    (e: unknown) => e,
  );
  expect(err).toBeInstanceOf(HttpsError);
  expect((err as HttpsError).code).toBe(code);
  expect((err as HttpsError).details).toMatchObject({ reason });
  return err as HttpsError;
}

async function attendanceFor(user: string) {
  const snap = await db.collection("attendance").where("userId", "==", user).get();
  return snap.docs.map((d) => d.data()).sort((a, b) => a.timestamp.toMillis() - b.timestamp.toMillis());
}

describe("check-in / check-out", () => {
  test("first tap is an on-time check-in", async () => {
    const at = manila(DAY, "07:55:00");
    const res = await tap(at);
    expect(res).toMatchObject({ type: "in", late: false, date: DAY, tagId: "main", tagLabel: "Main entrance" });

    const [rec] = await attendanceFor("alice");
    expect(rec).toMatchObject({ userId: "alice", userName: "Alice", tagId: "main", tagUid: UID, type: "in", date: DAY, late: false });
    expect((rec.timestamp as Timestamp).toDate()).toEqual(at);

    const day = (await db.doc(`attendanceDays/alice_${DAY}`).get()).data()!;
    expect(day).toMatchObject({ userId: "alice", date: DAY, lastType: "in", tapCount: 1, late: false });
    expect(day.firstIn.toDate()).toEqual(at);
  });

  test("alternates in/out across the day, keeping firstIn and late from the first check-in", async () => {
    const types = [];
    for (const t of ["08:10:00", "12:00:00", "13:00:00", "17:30:00"]) {
      types.push((await tap(manila(DAY, t))).type);
    }
    expect(types).toEqual(["in", "out", "in", "out"]);

    const recs = await attendanceFor("alice");
    expect(recs.map((r) => r.late)).toEqual([true, false, false, false]);

    const day = (await db.doc(`attendanceDays/alice_${DAY}`).get()).data()!;
    expect(day.tapCount).toBe(4);
    expect(day.late).toBe(true);
    expect(day.firstIn.toDate()).toEqual(manila(DAY, "08:10:00"));
    expect(day.lastOut.toDate()).toEqual(manila(DAY, "17:30:00"));
    expect(day.lastType).toBe("out");
  });

  test("a new day starts with a check-in even if yesterday was left open", async () => {
    await tap(manila(DAY, "08:00:00"));
    const res = await tap(manila("2026-10-27", "07:45:00"));
    expect(res).toMatchObject({ type: "in", date: "2026-10-27", late: false });
  });

  test("day boundary follows office time zone, not UTC", async () => {
    // 2026-10-26 23:30 UTC is already 07:30 on the 27th in Manila
    const res = await tap(new Date("2026-10-26T23:30:00Z"));
    expect(res.date).toBe("2026-10-27");
  });
});

describe("late threshold", () => {
  test.each([
    ["07:59:59", false],
    ["08:00:00", false],
    ["08:00:59", false],
    ["08:01:00", true],
  ])("check-in at %s -> late=%s", async (time, late) => {
    expect((await tap(manila(DAY, time))).late).toBe(late);
  });

  test("uses the configured lateTime", async () => {
    await db.doc("settings/app").update({ lateTime: "09:00" });
    expect((await tap(manila(DAY, "08:30:00"))).late).toBe(false);
  });

  test("falls back to defaults when settings doc is missing", async () => {
    await db.doc("settings/app").delete();
    expect((await tap(manila(DAY, "08:05:00"))).late).toBe(true);
  });
});

describe("duplicate taps", () => {
  test("rejects a second tap within 2 minutes and writes nothing", async () => {
    await tap(manila(DAY, "08:00:00"));
    const err = await expectReason(tap(manila(DAY, "08:01:30")), "failed-precondition", "DUPLICATE_TAP");
    expect(err.details).toMatchObject({ lastType: "in", retryAfterSeconds: 30 });
    expect(await attendanceFor("alice")).toHaveLength(1);
    expect((await db.doc(`attendanceDays/alice_${DAY}`).get()).data()!.tapCount).toBe(1);
  });

  test("accepts a tap exactly at the window boundary", async () => {
    await tap(manila(DAY, "08:00:00"));
    expect((await tap(manila(DAY, "08:02:00"))).type).toBe("out");
  });

  test("the window applies across different tags", async () => {
    await db.doc("tags/side").set({ uid: "04000000000001", label: "Side door", active: true });
    await tap(manila(DAY, "08:00:00"));
    await expectReason(
      tap(manila(DAY, "08:00:30"), { tagUid: "04000000000001", tagUrl: "https://att.example.com/tag/side" }),
      "failed-precondition",
      "DUPLICATE_TAP",
    );
  });

  test("concurrent taps produce exactly one record", async () => {
    const at = manila(DAY, "08:00:00");
    const results = await Promise.allSettled([tap(at), tap(at), tap(at)]);
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect(await attendanceFor("alice")).toHaveLength(1);
  });
});

describe("tag verification", () => {
  test("rejects a UID that does not match the registered tag", async () => {
    await expectReason(
      tap(manila(DAY, "08:00:00"), { tagUid: "04000000000000", tagUrl: URL_MAIN }),
      "permission-denied",
      "TAG_UID_MISMATCH",
    );
    expect(await attendanceFor("alice")).toHaveLength(0);
  });

  test("accepts the UID in any common formatting", async () => {
    const res = await tap(manila(DAY, "08:00:00"), { tagUid: "04:a1:b2:c3:d4:e5:f6", tagUrl: URL_MAIN });
    expect(res.type).toBe("in");
  });

  test("rejects an unregistered tag", async () => {
    await expectReason(
      tap(manila(DAY, "08:00:00"), { tagUid: UID, tagUrl: "https://att.example.com/tag/nope" }),
      "not-found",
      "TAG_NOT_REGISTERED",
    );
  });

  test("rejects an inactive tag", async () => {
    await expectReason(
      tap(manila(DAY, "08:00:00"), { tagUid: "04FFFFFFFFFFFF", tagUrl: "https://att.example.com/tag/old" }),
      "failed-precondition",
      "TAG_INACTIVE",
    );
  });

  test("rejects URLs from another domain", async () => {
    await expectReason(
      tap(manila(DAY, "08:00:00"), { tagUid: UID, tagUrl: "https://evil.example.net/tag/main" }),
      "invalid-argument",
      "INVALID_TAG_URL",
    );
  });

  test.each([
    ["missing input", undefined],
    ["missing uid", { tagUrl: URL_MAIN }],
    ["malformed uid", { tagUid: "hello", tagUrl: URL_MAIN }],
  ])("rejects %s", async (_n, input) => {
    await expectReason(
      recordTap(db, "alice", input as never, manila(DAY, "08:00:00")),
      "invalid-argument",
      "INVALID_INPUT",
    );
  });
});

describe("user checks", () => {
  test("rejects an inactive user", async () => {
    await expectReason(tap(manila(DAY, "08:00:00"), undefined, "zed"), "permission-denied", "USER_INACTIVE");
  });
  test("rejects a signed-in user with no user doc", async () => {
    await expectReason(tap(manila(DAY, "08:00:00"), undefined, "ghost"), "permission-denied", "USER_NOT_FOUND");
  });
});
