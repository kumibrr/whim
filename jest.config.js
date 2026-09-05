module.exports = {
  projects: [
    {
      displayName: 'unit',
      preset: 'jest-expo',
      testMatch: [
        '<rootDir>/src/**/*.test.[jt]s?(x)',
        '<rootDir>/packages/**/*.test.[jt]s?(x)',
      ],
      testPathIgnorePatterns: ['\\.integration\\.test\\.'],
    },
    {
      displayName: 'integration',
      preset: 'jest-expo',
      testMatch: [
        '<rootDir>/src/**/*.integration.test.[jt]s?(x)',
        '<rootDir>/packages/**/*.integration.test.[jt]s?(x)',
      ],
    },
  ],
};
