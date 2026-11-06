import { spawnSync } from 'node:child_process';

// Native XCTest can leave an automation session attached between test runners.
// Restart only the simulator owned by this E2E run before starting Maestro.
const simulator = process.argv[2];
if (!simulator) throw new Error('An E2E simulator UDID is required.');
const shutdown = spawnSync('xcrun', ['simctl', 'shutdown', simulator], { encoding: 'utf8' });
if (shutdown.error) throw shutdown.error;
const shutdownOutput = (shutdown.stdout ?? '') + (shutdown.stderr ?? '');
if (shutdown.status !== 0 && !/Unable to shutdown device in current state: Shutdown/.test(shutdownOutput)) {
  if (shutdownOutput) process.stderr.write(shutdownOutput);
  throw new Error(`Simulator ${simulator} shutdown failed; refusing to start E2E.`);
}

// -b also boots when needed, and tolerates another client booting the device
// after shutdown. A separate `simctl boot` races with those clients.
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
