import { csvCell, toCsv } from "../../src/lib/csv";

describe("csvCell", () => {
  test.each([
    ["plain", "plain"],
    ["a,b", '"a,b"'],
    ['say "hi"', '"say ""hi"""'],
    ["line\nbreak", '"line\nbreak"'],
    [42, "42"],
    [null, ""],
    [undefined, ""],
  ])("%p -> %p", (v, out) => expect(csvCell(v)).toBe(out));

  test.each(["=SUM(A1)", "+1", "-1+2", "@cmd", "\tx"])("neutralizes formula %p", (v) => {
    expect(csvCell(v).replace(/^"/, "").startsWith("'")).toBe(true);
  });
});

test("toCsv adds BOM, header and CRLF rows", () => {
  expect(toCsv(["A", "B"], [["María", "x,y"]])).toBe('﻿A,B\r\nMaría,"x,y"\r\n');
});
