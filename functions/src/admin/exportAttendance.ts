import { Firestore, Timestamp } from "firebase-admin/firestore";
import { getFirestore } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";
import { z } from "zod";
import { requireAdmin } from "../lib/auth";
import { toCsv } from "../lib/csv";
import { parseInput } from "../lib/errors";
import { getSettings } from "../lib/settings";
import { datesBetween, formatLocalHHMM, isIsoDate, isoWeekdayOf, toLocalTime } from "../lib/time";

const MAX_RANGE_DAYS = 366;

const isoDate = z.string().refine(isIsoDate, "must be a date in YYYY-MM-DD form");
const bothValid = (v: { from: unknown; to: unknown }) =>
  typeof v.from === "string" && typeof v.to === "string" && isIsoDate(v.from) && isIsoDate(v.to);

export const exportSchema = z
  .object({
    from: isoDate,
    to: isoDate,
    /** daily = one row per employee per day (payroll); raw = every tap. */
    format: z.enum(["daily", "raw"]).default("daily"),
  })
  // Zod runs object refinements even when a field failed, so guard on valid dates.
  .refine((v) => !bothValid(v) || v.from <= v.to, { message: "from must not be after to", path: ["from"] })
  .refine((v) => !bothValid(v) || v.from > v.to || datesBetween(v.from, v.to).length <= MAX_RANGE_DAYS, {
    message: `range must be at most ${MAX_RANGE_DAYS} days`,
    path: ["to"],
  });
export type ExportInput = z.input<typeof exportSchema>;

export interface ExportResult {
  filename: string;
  csv: string;
  rowCount: number;
}

interface UserInfo {
  uid: string;
  name: string;
  email: string;
  employeeId: string;
  active: boolean;
  trackAttendance: boolean;
  createdDate?: string;
  deactivatedDate?: string;
}

interface Tap {
  userId: string;
  type: "in" | "out";
  at: Date;
  date: string;
  tagId: string;
  late: boolean;
}

export const DAILY_HEADER = [
  "Date",
  "Weekday",
  "Employee ID",
  "Name",
  "Email",
  "Status",
  "First In",
  "Last Out",
  "Hours Worked",
  "Taps",
  "Notes",
];
export const RAW_HEADER = ["Date", "Time", "Employee ID", "Name", "Email", "Type", "Tag", "Late"];
const WEEKDAY_NAMES = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** Hours between consecutive in -> out pairs; an unmatched trailing "in" is not counted. */
export function workedHours(taps: Tap[]): number {
  let ms = 0;
  let openIn: Date | undefined;
  for (const t of taps) {
    if (t.type === "in") openIn = t.at;
    else if (openIn) {
      ms += t.at.getTime() - openIn.getTime();
      openIn = undefined;
    }
  }
  return ms / 3_600_000;
}

export async function exportAttendanceCore(db: Firestore, rawInput: unknown, now = new Date()): Promise<ExportResult> {
  const input = parseInput(exportSchema, rawInput);
  const settings = await getSettings(db);
  const tz = settings.timezone;
  const localDate = (ts: unknown) => (ts instanceof Timestamp ? toLocalTime(ts.toDate(), tz).date : undefined);

  const [usersSnap, tapsSnap] = await Promise.all([
    db.collection("users").get(),
    db
      .collection("attendance")
      .where("date", ">=", input.from)
      .where("date", "<=", input.to)
      .orderBy("date")
      .orderBy("timestamp")
      .get(),
  ]);

  const users = new Map<string, UserInfo>();
  for (const d of usersSnap.docs) {
    const u = d.data();
    users.set(d.id, {
      uid: d.id,
      name: u.displayName ?? "",
      email: u.email ?? "",
      employeeId: u.employeeId ?? "",
      active: u.active === true,
      trackAttendance: u.trackAttendance !== false,
      createdDate: localDate(u.createdAt),
      deactivatedDate: localDate(u.deactivatedAt),
    });
  }
  const userOf = (uid: string, fallbackName = ""): UserInfo =>
    users.get(uid) ?? { uid, name: fallbackName, email: "", employeeId: "", active: false, trackAttendance: false };

  const taps: Tap[] = tapsSnap.docs.map((d) => {
    const r = d.data();
    if (!users.has(r.userId)) users.set(r.userId, userOf(r.userId, r.userName));
    return {
      userId: r.userId,
      type: r.type,
      at: (r.timestamp as Timestamp).toDate(),
      date: r.date,
      tagId: r.tagId,
      late: r.late === true,
    };
  });

  const byName = (a: UserInfo, b: UserInfo) => a.name.localeCompare(b.name) || a.uid.localeCompare(b.uid);
  const fileBase = `attendance_${input.format}_${input.from}_to_${input.to}.csv`;

  if (input.format === "raw") {
    const rows = taps.map((t) => {
      const u = userOf(t.userId);
      return [t.date, formatLocalHHMM(t.at, tz), u.employeeId, u.name, u.email, t.type === "in" ? "IN" : "OUT", t.tagId, t.late ? "Yes" : ""];
    });
    return { filename: fileBase, csv: toCsv(RAW_HEADER, rows), rowCount: rows.length };
  }

  // daily
  const tapsByUserDay = new Map<string, Tap[]>();
  for (const t of taps) {
    const key = `${t.userId}|${t.date}`;
    (tapsByUserDay.get(key) ?? tapsByUserDay.set(key, []).get(key)!).push(t);
  }
  const today = toLocalTime(now, tz).date;
  const sortedUsers = [...users.values()].sort(byName);
  const rows: unknown[][] = [];

  for (const date of datesBetween(input.from, input.to)) {
    const weekday = isoWeekdayOf(date);
    for (const u of sortedUsers) {
      const dayTaps = tapsByUserDay.get(`${u.uid}|${date}`);
      if (dayTaps?.length) {
        const firstIn = dayTaps.find((t) => t.type === "in");
        const outs = dayTaps.filter((t) => t.type === "out");
        const lastOut = outs[outs.length - 1];
        const openAtEnd = dayTaps[dayTaps.length - 1].type === "in";
        rows.push([
          date,
          WEEKDAY_NAMES[weekday],
          u.employeeId,
          u.name,
          u.email,
          firstIn?.late ? "Late" : "Present",
          firstIn ? formatLocalHHMM(firstIn.at, tz) : "",
          lastOut ? formatLocalHHMM(lastOut.at, tz) : "",
          workedHours(dayTaps).toFixed(2),
          dayTaps.length,
          openAtEnd ? "Missing check-out" : "",
        ]);
        continue;
      }
      const expected =
        u.trackAttendance &&
        settings.workDays.includes(weekday) &&
        date <= today &&
        (!u.createdDate || date >= u.createdDate) &&
        (u.active || (u.deactivatedDate !== undefined && date < u.deactivatedDate));
      if (expected) {
        rows.push([date, WEEKDAY_NAMES[weekday], u.employeeId, u.name, u.email, "Absent", "", "", "0.00", 0, ""]);
      }
    }
  }
  return { filename: fileBase, csv: toCsv(DAILY_HEADER, rows), rowCount: rows.length };
}

export const exportAttendanceCsv = onCall({ timeoutSeconds: 120, memory: "512MiB" }, async (request) => {
  const db = getFirestore();
  await requireAdmin(request, db);
  return exportAttendanceCore(db, request.data);
});
