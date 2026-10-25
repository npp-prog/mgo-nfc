/** @type {import('jest').Config} */
module.exports = {
  testEnvironment: "node",
  roots: ["<rootDir>/test"],
  transform: {
    "^.+\\.ts$": ["ts-jest", { tsconfig: "<rootDir>/tsconfig.test.json" }],
  },
  moduleNameMapper: { "^jwks-rsa$": "<rootDir>/test/helpers/jwks-rsa-stub.js" },
  testTimeout: 20000,
  // Suites share the emulator project and clear it between tests.
  maxWorkers: 1,
};
