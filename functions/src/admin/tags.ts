import { FieldValue, Firestore } from "firebase-admin/firestore";
import { getFirestore } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";
import { z } from "zod";
import { requireAdmin } from "../lib/auth";
import { fail, parseInput } from "../lib/errors";
import { getSettings } from "../lib/settings";
import { normalizeTagUid, TAG_ID_PATTERN } from "../lib/tags";

export const registerTagSchema = z.object({
  tagId: z.string().regex(TAG_ID_PATTERN, "1-64 letters, digits, - or _"),
  tagUid: z.string().transform((v, ctx) => {
    const uid = normalizeTagUid(v);
    if (!uid) {
      ctx.addIssue({ code: "custom", message: "not a valid NFC UID" });
      return z.NEVER;
    }
    return uid;
  }),
  label: z.string().trim().min(1).max(100),
  location: z.string().trim().max(200).default(""),
  /** Re-point an existing tagId to a new physical tag (e.g. a damaged tag was replaced). */
  replace: z.boolean().default(false),
});
export type RegisterTagInput = z.input<typeof registerTagSchema>;

export interface RegisterTagResult {
  tagId: string;
  tagUid: string;
  /** URL the app must write to the tag as an NDEF URI record. */
  url: string;
  created: boolean;
}

/**
 * Saves a tag. Idempotent for the same tagId + UID, so the app can call it
 * again if writing the NDEF record failed. A UID can belong to only one tag.
 */
export async function registerTagCore(db: Firestore, actorUid: string, rawInput: unknown): Promise<RegisterTagResult> {
  const input = parseInput(registerTagSchema, rawInput);
  const { tagUrlBase } = await getSettings(db);
  if (!tagUrlBase) {
    fail("failed-precondition", "TAG_URL_BASE_NOT_SET", "Set the tag URL base in Settings before registering tags.");
  }
  const url = `${tagUrlBase}${input.tagId}`;
  const ref = db.doc(`tags/${input.tagId}`);

  return db.runTransaction(async (tx) => {
    const [existing, sameUid] = await Promise.all([
      tx.get(ref),
      tx.get(db.collection("tags").where("uid", "==", input.tagUid).limit(2)),
    ]);
    const owner = sameUid.docs.find((d) => d.id !== input.tagId);
    if (owner) {
      fail("already-exists", "TAG_UID_TAKEN", `This physical tag is already registered as "${owner.id}".`, {
        tagId: owner.id,
      });
    }
    if (existing.exists && existing.get("uid") !== input.tagUid && !input.replace) {
      fail("already-exists", "TAG_ID_TAKEN", `Tag ID "${input.tagId}" is already used by another tag.`);
    }

    const data: Record<string, unknown> = {
      uid: input.tagUid,
      label: input.label,
      location: input.location,
      active: true,
      url,
      registeredBy: actorUid,
      registeredAt: FieldValue.serverTimestamp(),
    };
    tx.set(ref, data);
    return { tagId: input.tagId, tagUid: input.tagUid, url, created: !existing.exists };
  });
}

export const registerTag = onCall(async (request) => {
  const db = getFirestore();
  const actor = await requireAdmin(request, db);
  return registerTagCore(db, actor, request.data);
});
