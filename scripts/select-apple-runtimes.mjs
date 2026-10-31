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
  const supported = runtime.supportedDeviceTypes?.map(type => type.identifier);
  const match = types.find(type => type.productFamily === family
    && (supported === undefined || supported.includes(type.identifier))
    && Number.isFinite(type.minRuntimeVersion) && Number.isFinite(type.maxRuntimeVersion)
    && type.minRuntimeVersion <= version && version <= type.maxRuntimeVersion);
  if (!match) throw new Error(`No compatible ${family} simulator device type for runtime ${runtime.version}.`);
  return match;
}

// Keep the primary portrait-phone CI matrix stable as Xcode adds new form factors.
export function selectCompatibleSimulators(runtimes, types, {
  iphoneType = 'com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro',
  watchType = 'com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-10-46mm',
} = {}) {
  const iphone = types.find(type => type.identifier === iphoneType && type.productFamily === 'iPhone');
  const watchDevice = types.find(type => type.identifier === watchType && type.productFamily === 'Apple Watch');
  if (!iphone) throw new Error(`The configured iPhone CI device type is not installed: ${iphoneType}`);
  if (!watchDevice) throw new Error(`The configured Watch CI device type is not installed: ${watchType}`);
  const eligible = runtimes.filter(runtime => {
    const type = runtime.identifier.includes('.iOS-') ? iphone
      : runtime.identifier.includes('.watchOS-') ? watchDevice : null;
    if (!type) return false;
    try { selectCompatibleDeviceType([type], type.productFamily, runtime); return true; }
    catch { return false; }
  });
  let selection;
  try { selection = selectCompatibleRuntimes(eligible); }
  catch (error) {
    const available = runtimes.filter(runtime => runtime.isAvailable).map(runtime => runtime.identifier).join(', ');
    throw new Error(`${error.message} Configured CI devices: ${iphoneType}, ${watchType}. Available runtimes: ${available}`, { cause: error });
  }
  return { ...selection, iphone, watchDevice };
}

async function main() {
  const runtimeList = JSON.parse(await readFile(process.argv[2], 'utf8'));
  let selection;
  const identifiers = [];
  if (process.argv[3]) {
    const { devicetypes } = JSON.parse(await readFile(process.argv[3], 'utf8'));
    selection = selectCompatibleSimulators(runtimeList.runtimes ?? [], devicetypes, {
      iphoneType: process.env.WHIM_CI_IPHONE_DEVICE_TYPE,
      watchType: process.env.WHIM_CI_WATCH_DEVICE_TYPE,
    });
    identifiers.push(selection.ios.identifier, selection.watch.identifier,
      selection.iphone.identifier, selection.watchDevice.identifier);
  } else {
    selection = selectCompatibleRuntimes(runtimeList.runtimes ?? []);
    identifiers.push(selection.ios.identifier, selection.watch.identifier);
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
