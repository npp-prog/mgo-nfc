import { FunctionsErrorCode, HttpsError } from "firebase-functions/v2/https";
import { z } from "zod";

/** Machine-readable reasons the app maps to user-facing messages. */
export type FailureReason =
  | "UNAUTHENTICATED"
  | "NOT_ADMIN"
  | "INVALID_INPUT"
  | "INVALID_TAG_URL"
  | "USER_NOT_FOUND"
  | "USER_INACTIVE"
  | "EMAIL_EXISTS"
  | "EMPLOYEE_ID_EXISTS"
  | "SELF_LOCKOUT"
  | "TAG_NOT_REGISTERED"
  | "TAG_INACTIVE"
  | "TAG_UID_MISMATCH"
  | "TAG_ID_TAKEN"
  | "TAG_UID_TAKEN"
  | "TAG_URL_BASE_NOT_SET"
  | "DUPLICATE_TAP";

export function fail(
  code: FunctionsErrorCode,
  reason: FailureReason,
  message: string,
  extra: Record<string, unknown> = {},
): never {
  throw new HttpsError(code, message, { reason, ...extra });
}

/** Validates callable input, throwing invalid-argument with field-level issues. */
export function parseInput<T extends z.ZodType>(schema: T, data: unknown): z.infer<T> {
  const result = schema.safeParse(data ?? {});
  if (!result.success) {
    const issues = result.error.issues.map((i) => ({ path: i.path.join("."), message: i.message }));
    const first = issues[0];
    fail("invalid-argument", "INVALID_INPUT", first.path ? `${first.path}: ${first.message}` : first.message, {
      issues,
    });
  }
  return result.data;
}
