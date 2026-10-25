import { HttpsError } from "firebase-functions/v2/https";

/** Asserts a promise rejects with an HttpsError of the given code and details.reason. */
export async function expectReason(p: Promise<unknown>, code: string, reason: string): Promise<HttpsError> {
  const err = await p.then(
    () => {
      throw new Error(`expected rejection with ${reason}`);
    },
    (e: unknown) => e,
  );
  expect(err).toBeInstanceOf(HttpsError);
  expect((err as HttpsError).code).toBe(code);
  expect((err as HttpsError).details).toMatchObject({ reason });
  return err as HttpsError;
}
