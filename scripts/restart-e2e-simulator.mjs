import { execFileSync } from 'node:child_process';

// Native XCTest can leave an automation session attached between test runners.
// Restart only the simulator owned by this E2E run before starting Maestro.
const simulator = process.argv[2];
if (!simulator) throw new Error('An E2E simulator UDID is required.');
for (const args of [['shutdown', simulator], ['boot', simulator], ['bootstatus', simulator, '-b']]) {
  execFileSync('xcrun', ['simctl', ...args], { stdio: 'inherit' });
}
