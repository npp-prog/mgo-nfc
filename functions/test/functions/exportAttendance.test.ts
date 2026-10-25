import { Firestore, Timestamp } from "firebase-admin/firestore";
import { DAILY_HEADER, exportAttendanceCore, RAW_HEADER } from "../../src/admin/exportAttendance";
import { recordTap } from "../../src/attendance/recordAttendance";
import { adminDb, clearFirestore, manila } from "../helpers/emulator";
import { expectReason } from "../helpers/errors";

let db: Firestore;
const UID = "04A1B2C3D4E5F6";
const input = { tagUid: UID, tagUrl: "https://att.example.com/tag/main" };
// Mon 2026-10-26 .. Sun 2026-11-01
const NOW = manila("2026-11-02", "09:00:00");

/** Parses our CSV output (no embedded newlines in test data) into objects keyed by header. */
function parse(csv: string): Record<string, string>[] {
  expect(csv.startsWith("﻿")).toBe(true);
  const lines = csv.slice(1).trimEnd().split("\r\n");
  const header = lines[0].split(",");
  return lines.slice(1).map((l) => Object.fromEntries(l.split(",").map((v, i) => [header[i], v])));
}

beforeAll(() => {
  db = adminDb();
});

beforeEach(async () => {
  await clearFirestore();
  const hired = Timestamp.fromDate(manila("2026-10-01", "00:00:00"));
  await db.doc("settings/app").set({
    lateTime: "08:00",
    timezone: "Asia/Manila",
    duplicateWindowSeconds: 120,
    tagUrlBase: "https://att.example.com/tag/",
    workDays: [1, 2, 3, 4, 5],
  });
  await db.doc("tags/main").set({ uid: UID, label: "Main", active: true });
  await db.doc("users/ana").set({ displayName: "Ana", email: "ana@x.com", employeeId: "E1", role: "employee", active: true, createdAt: hired });
  await db.doc("users/ben").set({ displayName: "Ben", email: "ben@x.com", employeeId: "E2", role: "employee", active: true, createdAt: hired });
  // Carl left on Wed 2026-10-28
  await db.doc("users/carl").set({
    displayName: "Carl",
    email: "carl@x.com",
    employeeId: "E3",
    role: "employee",
    active: false,
    createdAt: hired,
    deactivatedAt: Timestamp.fromDate(manila("2026-10-28", "12:00:00")),
  });
  // Dee joined Thu 2026-10-29
  await db.doc("users/dee").set({
    displayName: "Dee",
    email: "=HYPERLINK(evil)",
    employeeId: "E4",
    role: "employee",
    active: true,
    createdAt: Timestamp.fromDate(manila("2026-10-29", "07:00:00")),
  });

  // Ana: Mon on time with lunch break, Tue late, forgets checkout Wed
  await recordTap(db, "ana", input, manila("2026-10-26", "07:50:00"));
  await recordTap(db, "ana", input, manila("2026-10-26", "12:00:00"));
  await recordTap(db, "ana", input, manila("2026-10-26", "13:00:00"));
  await recordTap(db, "ana", input, manila("2026-10-26", "17:20:00"));
  await recordTap(db, "ana", input, manila("2026-10-27", "08:15:00"));
  await recordTap(db, "ana", input, manila("2026-10-27", "17:15:00"));
  await recordTap(db, "ana", input, manila("2026-10-28", "08:00:00"));
  // Ben: Saturday overtime only
  await recordTap(db, "ben", input, manila("2026-10-31", "09:00:00"));
  await recordTap(db, "ben", input, manila("2026-10-31", "12:30:00"));
});

test("daily export: present, late, missing checkout, hours with breaks", async () => {
  const res = await exportAttendanceCore(db, { from: "2026-10-26", to: "2026-10-28" }, NOW);
  expect(res.filename).toBe("attendance_daily_2026-10-26_to_2026-10-28.csv");
  expect(res.csv.slice(1).split("\r\n")[0]).toBe(DAILY_HEADER.join(","));
  const rows = parse(res.csv);
  const row = (date: string, name: string) => rows.find((r) => r.Date === date && r.Name === name);

  expect(row("2026-10-26", "Ana")).toMatchObject({
    Weekday: "Mon",
    "Employee ID": "E1",
    Status: "Present",
    "First In": "07:50",
    "Last Out": "17:20",
    "Hours Worked": "8.50",
    Taps: "4",
    Notes: "",
  });
  expect(row("2026-10-27", "Ana")).toMatchObject({ Status: "Late", "First In": "08:15", "Hours Worked": "9.00" });
  expect(row("2026-10-28", "Ana")).toMatchObject({ Status: "Present", "Last Out": "", "Hours Worked": "0.00", Notes: "Missing check-out" });
  expect(row("2026-10-26", "Ben")).toMatchObject({ Status: "Absent", Taps: "0" });
});

test("absences respect work days, hire date, deactivation date and today", async () => {
  const rows = parse((await exportAttendanceCore(db, { from: "2026-10-26", to: "2026-11-06" }, NOW)).csv);
  const statuses = (name: string) => rows.filter((r) => r.Name === name).map((r) => `${r.Date}:${r.Status}`);

  // Carl absent Mon+Tue, nothing from his deactivation day on
  expect(statuses("Carl")).toEqual(["2026-10-26:Absent", "2026-10-27:Absent"]);
  // Dee only from her start date (Thu), weekends skipped, through today (Mon 11-02) but not the future
  expect(statuses("Dee")).toEqual(["2026-10-29:Absent", "2026-10-30:Absent", "2026-11-02:Absent"]);
  // Ben's Saturday work appears even though Saturday is not a work day
  expect(statuses("Ben")).toContain("2026-10-31:Present");
  expect(rows.find((r) => r.Name === "Ben" && r.Date === "2026-10-31")!["Hours Worked"]).toBe("3.50");
  // rows are ordered by date, then name
  const order = rows.map((r) => `${r.Date}|${r.Name}`);
  expect(order).toEqual([...order].sort());
});

test("users with trackAttendance=false are never absent but their taps still appear", async () => {
  await db.doc("users/ana").update({ trackAttendance: false });
  await db.doc("users/ben").update({ trackAttendance: false });
  const rows = parse((await exportAttendanceCore(db, { from: "2026-10-26", to: "2026-11-02" }, NOW)).csv);
  expect(rows.filter((r) => r.Name === "Ben").map((r) => `${r.Date}:${r.Status}`)).toEqual(["2026-10-31:Present"]);
  expect(rows.filter((r) => r.Name === "Ana").map((r) => r.Status)).toEqual(["Present", "Late", "Present"]);
});

test("neutralizes spreadsheet formulas in user-controlled fields", async () => {
  const res = await exportAttendanceCore(db, { from: "2026-10-29", to: "2026-10-29" }, NOW);
  expect(res.csv).toContain("'=HYPERLINK(evil)");
  expect(res.csv).not.toMatch(/,=HYPERLINK/);
});

test("raw export lists every tap in local time", async () => {
  const res = await exportAttendanceCore(db, { from: "2026-10-26", to: "2026-10-27", format: "raw" }, NOW);
  expect(res.csv.slice(1).split("\r\n")[0]).toBe(RAW_HEADER.join(","));
  const rows = parse(res.csv);
  expect(res.rowCount).toBe(6);
  expect(rows.map((r) => `${r.Time} ${r.Type}`)).toEqual([
    "07:50 IN",
    "12:00 OUT",
    "13:00 IN",
    "17:20 OUT",
    "08:15 IN",
    "17:15 OUT",
  ]);
  expect(rows[4]).toMatchObject({ Date: "2026-10-27", Name: "Ana", Late: "Yes", Tag: "main" });
});

test.each([
  ["bad date", { from: "2026-13-01", to: "2026-12-01" }],
  ["reversed range", { from: "2026-10-28", to: "2026-10-26" }],
  ["range too long", { from: "2025-01-01", to: "2026-10-26" }],
  ["bad format", { from: "2026-10-26", to: "2026-10-26", format: "xlsx" }],
])("rejects %s", async (_n, input) => {
  await expectReason(exportAttendanceCore(db, input, NOW), "invalid-argument", "INVALID_INPUT");
});
