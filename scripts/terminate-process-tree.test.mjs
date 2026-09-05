import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import test from 'node:test';

import { terminateProcessTree } from './terminate-process-tree.mjs';

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

function isAlive(processID) {
  try {
    process.kill(processID, 0);
    return true;
  } catch {
    return false;
  }
}

async function waitUntilStopped(processID) {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (!isAlive(processID)) return;
    await sleep(20);
  }
}

test('terminates both a spawned parent and its descendant', async (t) => {
  const parent = spawn(
    process.execPath,
    [
      '-e',
      `
        const { spawn } = require('node:child_process');
        const child = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {
          stdio: 'ignore',
        });
        process.stdout.write(String(child.pid));
        setInterval(() => {}, 1000);
      `,
    ],
    { stdio: ['ignore', 'pipe', 'inherit'] },
  );
  const [childPIDOutput] = await once(parent.stdout, 'data');
  const childProcessID = Number(childPIDOutput.toString());
  t.after(() => {
    for (const processID of [parent.pid, childProcessID]) {
      if (isAlive(processID)) process.kill(processID, 'SIGKILL');
    }
  });

  await terminateProcessTree(parent.pid);
  await Promise.all([waitUntilStopped(parent.pid), waitUntilStopped(childProcessID)]);

  assert.equal(isAlive(parent.pid), false);
  assert.equal(isAlive(childProcessID), false);
});
