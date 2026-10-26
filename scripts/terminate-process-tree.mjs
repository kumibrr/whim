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
  // Snapshot the whole tree before any signal can exit a shell and reparent children.
  async function descendantsBeforeParents(pid) {
    const children = await childProcessIDsFn(pid);
    const descendants = await Promise.all(children.map(descendantsBeforeParents));
    return [...descendants.flat(), pid];
  }
  for (const pid of await descendantsBeforeParents(processID)) terminateFn(pid);
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
