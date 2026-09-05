import { execFile } from 'node:child_process';
import { pathToFileURL } from 'node:url';

function childProcessIDs(processID) {
  return new Promise((resolve, reject) => {
    execFile('pgrep', ['-P', String(processID)], (error, stdout) => {
      if (error && error.code !== 1) {
        reject(error);
        return;
      }
      resolve(
        stdout
          .trim()
          .split(/\s+/)
          .filter(Boolean)
          .map(Number),
      );
    });
  });
}

function terminate(processID) {
  try {
    process.kill(processID, 'SIGTERM');
  } catch (error) {
    if (error.code !== 'ESRCH') throw error;
  }
}

export async function terminateProcessTree(
  processID,
  { childProcessIDsFn = childProcessIDs, terminateFn = terminate } = {},
) {
  const children = await childProcessIDsFn(processID);
  terminateFn(processID);
  await Promise.all(
    children.map((childProcessID) =>
      terminateProcessTree(childProcessID, { childProcessIDsFn, terminateFn }),
    ),
  );
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const processID = Number(process.argv[2]);
  if (!Number.isSafeInteger(processID) || processID <= 0) {
    console.error('Usage: node scripts/terminate-process-tree.mjs <process-id>');
    process.exitCode = 1;
  } else {
    await terminateProcessTree(processID);
  }
}
