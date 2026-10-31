import { execFileSync, spawnSync } from 'node:child_process';

// Native XCTest can leave an automation session attached between test runners.
// Restart only the simulator owned by this E2E run before starting Maestro.
const simulator = process.argv[2];
if (!simulator) throw new Error('An E2E simulator UDID is required.');
for (const args of [['shutdown', simulator], ['boot', simulator]]) {
  execFileSync('xcrun', ['simctl', ...args], { stdio: 'inherit' });
}

// bootstatus can exit zero even when its terminal state is Data Migration Failed.
const result = spawnSync('xcrun', ['simctl', 'bootstatus', simulator, '-b'], { encoding: 'utf8' });
if (result.stdout) process.stdout.write(result.stdout);
if (result.stderr) process.stderr.write(result.stderr);
if (result.error) throw result.error;
const output = (result.stdout ?? '') + (result.stderr ?? '');
const failedTerminal = [...output.matchAll(/Status=(\d+),\s*isTerminal=YES/g)]
  .some(match => match[1] !== '4294967295');
if (result.status !== 0 || failedTerminal || /Data Migration Failed/i.test(output)) {
  throw new Error(`Simulator ${simulator} boot failed; refusing to start E2E.`);
}
if (!/Finished|Device already booted/i.test(output)) {
  throw new Error(`Simulator ${simulator} did not report a healthy boot.`);
}
