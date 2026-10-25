/**
 * Normalizes an NFC UID to uppercase hex without separators
 * ("04:a1:b2..." -> "04A1B2..."). Returns null if it is not a plausible UID
 * (4, 7 or 10 bytes per ISO 14443).
 */
export function normalizeTagUid(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const hex = raw.replace(/[\s:-]/g, "").toUpperCase();
  if (!/^[0-9A-F]+$/.test(hex)) return null;
  return [8, 14, 20].includes(hex.length) ? hex : null;
}

export const TAG_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

/**
 * Extracts the tagId from an NDEF URL of the form https://<domain>/tag/<tagId>.
 * When `base` is set (e.g. "https://att.example.com/tag/"), the URL must start
 * with it. Returns null for anything else.
 */
export function parseTagUrl(raw: unknown, base = ""): string | null {
  if (typeof raw !== "string" || raw.length > 512) return null;
  let url: URL;
  try {
    url = new URL(raw.trim());
  } catch {
    return null;
  }
  if (url.protocol !== "https:" || url.search || url.hash) return null;
  if (base) {
    const b = new URL(base);
    if (url.host.toLowerCase() !== b.host.toLowerCase()) return null;
  }
  const m = /^\/tag\/([^/]+)\/?$/.exec(url.pathname);
  if (!m) return null;
  const tagId = decodeURIComponent(m[1]);
  return TAG_ID_PATTERN.test(tagId) ? tagId : null;
}
