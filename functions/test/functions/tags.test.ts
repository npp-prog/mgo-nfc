import { Firestore } from "firebase-admin/firestore";
import { registerTagCore } from "../../src/admin/tags";
import { adminDb, clearFirestore } from "../helpers/emulator";
import { expectReason } from "../helpers/errors";

let db: Firestore;
const tag = { tagId: "main", tagUid: "04:a1:b2:c3:d4:e5:f6", label: "Main entrance", location: "Lobby" };

beforeAll(() => {
  db = adminDb();
});

beforeEach(async () => {
  await clearFirestore();
  await db.doc("settings/app").set({ tagUrlBase: "https://att.example.com/tag/" });
});

test("registers a tag with normalized UID and returns the URL to write", async () => {
  const res = await registerTagCore(db, "boss", tag);
  expect(res).toEqual({ tagId: "main", tagUid: "04A1B2C3D4E5F6", url: "https://att.example.com/tag/main", created: true });
  expect((await db.doc("tags/main").get()).data()).toMatchObject({
    uid: "04A1B2C3D4E5F6",
    label: "Main entrance",
    location: "Lobby",
    active: true,
    url: "https://att.example.com/tag/main",
    registeredBy: "boss",
  });
});

test("is idempotent for the same tag and UID (retry after a failed NDEF write)", async () => {
  await registerTagCore(db, "boss", tag);
  const res = await registerTagCore(db, "boss", { ...tag, label: "Front door" });
  expect(res.created).toBe(false);
  expect((await db.doc("tags/main").get()).get("label")).toBe("Front door");
});

test("rejects a physical tag already registered under another ID", async () => {
  await registerTagCore(db, "boss", tag);
  const err = await expectReason(registerTagCore(db, "boss", { ...tag, tagId: "side" }), "already-exists", "TAG_UID_TAKEN");
  expect(err.details).toMatchObject({ tagId: "main" });
});

test("rejects reusing a tag ID for a different physical tag unless replace is set", async () => {
  await registerTagCore(db, "boss", tag);
  const other = { ...tag, tagUid: "04000000000001" };
  await expectReason(registerTagCore(db, "boss", other), "already-exists", "TAG_ID_TAKEN");
  await registerTagCore(db, "boss", { ...other, replace: true });
  expect((await db.doc("tags/main").get()).get("uid")).toBe("04000000000001");
});

test("re-activates a deactivated tag when re-registered", async () => {
  await registerTagCore(db, "boss", tag);
  await db.doc("tags/main").update({ active: false });
  await registerTagCore(db, "boss", tag);
  expect((await db.doc("tags/main").get()).get("active")).toBe(true);
});

test("requires tagUrlBase in settings", async () => {
  await db.doc("settings/app").delete();
  await expectReason(registerTagCore(db, "boss", tag), "failed-precondition", "TAG_URL_BASE_NOT_SET");
});

test.each([
  ["bad tag id", { tagId: "has space" }],
  ["bad uid", { tagUid: "zz" }],
  ["missing label", { label: "" }],
])("rejects %s", async (_n, patch) => {
  await expectReason(registerTagCore(db, "boss", { ...tag, ...patch }), "invalid-argument", "INVALID_INPUT");
});
