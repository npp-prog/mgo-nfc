// Jest-only stub. firebase-admin/auth requires jwks-rsa, which requires the
// ESM-only `jose` package that Jest's CommonJS runtime cannot load on Node 22.
// Tests never verify ID tokens in-process (the Functions emulator does that),
// so a stub is sufficient.
module.exports = function jwksClient() {
  throw new Error("jwks-rsa is stubbed in tests");
};
