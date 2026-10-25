import { normalizeTagUid, parseTagUrl } from "../../src/lib/tags";

describe("normalizeTagUid", () => {
  test.each([
    ["04A1B2C3D4E5F6", "04A1B2C3D4E5F6"],
    ["04:a1:b2:c3:d4:e5:f6", "04A1B2C3D4E5F6"],
    ["04-A1-B2-C3-D4-E5-F6", "04A1B2C3D4E5F6"],
    ["04 a1 b2 c3", "04A1B2C3"],
  ])("%s -> %s", (raw, expected) => expect(normalizeTagUid(raw)).toBe(expected));

  test.each([undefined, null, 42, "", "XYZ", "04A1B2", "04A1B2C3D4E5F6A"])("rejects %p", (raw) => {
    expect(normalizeTagUid(raw)).toBeNull();
  });
});

describe("parseTagUrl", () => {
  test("extracts tagId", () => {
    expect(parseTagUrl("https://att.example.com/tag/main-entrance")).toBe("main-entrance");
    expect(parseTagUrl("https://att.example.com/tag/side_door/")).toBe("side_door");
  });
  test("enforces the configured host", () => {
    const base = "https://att.example.com/tag/";
    expect(parseTagUrl("https://ATT.example.com/tag/main", base)).toBe("main");
    expect(parseTagUrl("https://evil.example.net/tag/main", base)).toBeNull();
  });
  test.each([
    "http://att.example.com/tag/main",
    "https://att.example.com/tags/main",
    "https://att.example.com/tag/",
    "https://att.example.com/tag/a/b",
    "https://att.example.com/tag/main?x=1",
    "https://att.example.com/tag/bad%20id",
    "not a url",
    42,
  ])("rejects %p", (raw) => expect(parseTagUrl(raw)).toBeNull());
});
