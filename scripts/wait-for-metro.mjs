import { pathToFileURL } from 'node:url';

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

function processAlive(processID) {
  try {
    process.kill(processID, 0);
    return true;
  } catch {
    return false;
  }
}

export async function waitForMetro({
  attempts = 90,
  fetchFn = fetch,
  processAliveFn = processAlive,
  processID,
  sleepFn = sleep,
  url = 'http://localhost:8081/status',
} = {}) {
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    if (processID !== undefined && !processAliveFn(processID)) return false;
    try {
      const response = await fetchFn(url, { signal: AbortSignal.timeout(1_000) });
      if (response.ok && (await response.text()).includes('packager-status:running')) {
        return processID === undefined || processAliveFn(processID);
      }
    } catch {
      // Metro is expected to reject connections while it starts.
    }
    await sleepFn(1_000);
  }
  return false;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const processID = process.argv[3] === undefined ? undefined : Number(process.argv[3]);
  if (!(await waitForMetro({ processID, url: process.argv[2] }))) process.exitCode = 1;
}
