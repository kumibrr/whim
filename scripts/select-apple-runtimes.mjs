import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

function compareVersions(left, right) {
  return right.version.localeCompare(left.version, undefined, { numeric: true });
}

function majorVersion(runtime) {
  return Number.parseInt(runtime.version.split('.')[0], 10);
}

function familyRuntimes(runtimes, family, minimumMajor) {
  return runtimes
    .filter(
      (runtime) =>
        runtime.isAvailable &&
        runtime.identifier.includes(`.${family}-`) &&
        majorVersion(runtime) >= minimumMajor,
    )
    .sort(compareVersions);
}

function requiredIOSMajor(watchRuntime) {
  const watchMajor = majorVersion(watchRuntime);
  return watchMajor < 26 ? watchMajor + 7 : watchMajor;
}

export function selectCompatibleRuntimes(runtimes) {
  const iosRuntimes = familyRuntimes(runtimes, 'iOS', 18);
  const watchRuntimes = familyRuntimes(runtimes, 'watchOS', 11);

  for (const watch of watchRuntimes) {
    const ios = iosRuntimes.find(
      (candidate) => majorVersion(candidate) === requiredIOSMajor(watch),
    );
    if (ios) return { ios, watch };
  }

  throw new Error(
    'No compatible simulator pair is installed (requires iOS 18+ and watchOS 11+ with matching platform generations).',
  );
}

async function main() {
  const runtimeList = JSON.parse(await readFile(process.argv[2], 'utf8'));
  const selection = selectCompatibleRuntimes(runtimeList.runtimes ?? []);
  process.stdout.write(`${selection.ios.identifier}|${selection.watch.identifier}`);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await main();
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
