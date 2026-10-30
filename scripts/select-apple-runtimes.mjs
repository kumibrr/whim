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

export function selectCompatibleDeviceType(types, family, runtime) {
  const [major, minor = 0, patch = 0] = runtime.version.split('.').map(Number);
  const version = major * 65536 + minor * 256 + patch;
  const match = types.find(type => type.productFamily === family
    && Number.isFinite(type.minRuntimeVersion) && Number.isFinite(type.maxRuntimeVersion)
    && type.minRuntimeVersion <= version && version <= type.maxRuntimeVersion);
  if (!match) throw new Error(`No compatible ${family} simulator device type for runtime ${runtime.version}.`);
  return match;
}

async function main() {
  const runtimeList = JSON.parse(await readFile(process.argv[2], 'utf8'));
  const selection = selectCompatibleRuntimes(runtimeList.runtimes ?? []);
  const identifiers = [selection.ios.identifier, selection.watch.identifier];
  if (process.argv[3]) {
    const { devicetypes } = JSON.parse(await readFile(process.argv[3], 'utf8'));
    identifiers.push(selectCompatibleDeviceType(devicetypes, 'iPhone', selection.ios).identifier,
      selectCompatibleDeviceType(devicetypes, 'Apple Watch', selection.watch).identifier);
  }
  process.stdout.write(identifiers.join('|'));
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await main();
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
