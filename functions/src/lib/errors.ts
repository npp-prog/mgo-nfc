import { FunctionsErrorCode, HttpsError } from "firebase-functions/v2/https";

/** Machine-readable reasons the app maps to user-facing messages. */
export type FailureReason =
  | "UNAUTHENTICATED"
  | "INVALID_INPUT"
  | "INVALID_TAG_URL"
  | "USER_NOT_FOUND"
  | "USER_INACTIVE"
  | "TAG_NOT_REGISTERED"
  | "TAG_INACTIVE"
  | "TAG_UID_MISMATCH"
  | "DUPLICATE_TAP";

export function fail(
  code: FunctionsErrorCode,
  reason: FailureReason,
  message: string,
  extra: Record<string, unknown> = {},
): never {
  throw new HttpsError(code, message, { reason, ...extra });
}
