import { isValidTimeZone, parseHHMM, toLocalTime } from "../../src/lib/time";

describe("toLocalTime", () => {
  test("converts UTC to Manila wall clock, crossing midnight", () => {
    // 2026-10-25 23:30 UTC = 2026-10-26 07:30 Manila (Monday)
    expect(toLocalTime(new Date("2026-10-25T23:30:00Z"), "Asia/Manila")).toEqual({
      date: "2026-10-26",
      minutes: 7 * 60 + 30,
      isoWeekday: 1,
    });
  });
  test("midnight is minute 0, Sunday is 7", () => {
    expect(toLocalTime(new Date("2026-10-24T16:00:00Z"), "Asia/Manila")).toEqual({
      date: "2026-10-25",
      minutes: 0,
      isoWeekday: 7,
    });
  });
});

describe("parseHHMM", () => {
  test.each([
    ["08:00", 480],
    ["00:00", 0],
    ["23:59", 1439],
  ])("%s -> %d", (v, m) => expect(parseHHMM(v)).toBe(m));
  test.each(["8:00", "24:00", "08:60", "", "0800"])("rejects %p", (v) => {
    expect(() => parseHHMM(v)).toThrow();
  });
});

test("isValidTimeZone", () => {
  expect(isValidTimeZone("Asia/Manila")).toBe(true);
  expect(isValidTimeZone("Mars/Base")).toBe(false);
});
