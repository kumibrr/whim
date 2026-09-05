import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ignoredDirectories = new Set([
  '.build',
  '.expo',
  '.git',
  'Pods',
  'build',
  'dist',
  'node_modules',
]);

const genericArchitectureDirectories = new Set([
  'adapters',
  'common',
  'components',
  'domain',
  'features',
  'ports',
  'services',
  'utils',
]);

async function filesBelow(root, relativeDirectory = '') {
  const absoluteDirectory = path.join(root, relativeDirectory);
  let entries;
  try {
    entries = await readdir(absoluteDirectory, { withFileTypes: true });
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }

  const files = [];
  for (const entry of entries) {
    const relativePath = path.join(relativeDirectory, entry.name);
    if (entry.isDirectory()) {
      if (!ignoredDirectories.has(entry.name)) {
        files.push(...(await filesBelow(root, relativePath)));
      }
    } else if (entry.isFile()) {
      files.push(relativePath);
    }
  }
  return files;
}

function implementationFor(testPath) {
  return testPath.replace(/(?:\.integration)?\.test(?=\.[^.]+$)/, '');
}

function sourceList(manifest, name) {
  const match = manifest.match(new RegExp(`let\\s+${name}\\s*=\\s*\\[([\\s\\S]*?)\\]`));
  if (!match) return null;
  return [...match[1].matchAll(/["']([^"']+)["']/g)].map((entry) => entry[1]);
}

function pbxObjects(project) {
  return new Map(
    [...project.matchAll(/([A-Za-z0-9_]+)\s+\/\*.*?\*\/\s*=\s*\{([\s\S]*?)\};/g)].map(
      ([, identifier, body]) => [identifier, body],
    ),
  );
}

function listIdentifiers(body, property) {
  const list = body.match(new RegExp(`${property}\\s*=\\s*\\(([\\s\\S]*?)\\);`));
  return list ? [...list[1].matchAll(/([A-Za-z0-9_]+)\s+\/\*/g)].map((match) => match[1]) : [];
}

function scalar(body, property) {
  const match = body.match(new RegExp(`${property}\\s*=\\s*("[^"]*"|[^;]+);`));
  return match?.[1].replace(/^"|"$/g, '').trim() ?? null;
}

function intendedXcodeTarget(file) {
  if (file.startsWith('src/watch/') && file.endsWith('.swift')) {
    return file.endsWith('.test.swift') ? 'WhimWatchTests' : 'WhimWatch';
  }
  if (file.startsWith('e2e/watch/') && file.endsWith('.e2e.test.swift')) {
    return 'WhimWatchUITests';
  }
  if (
    file.startsWith('packages/expo-whim/ios/') &&
    file.endsWith('.integration.test.swift')
  ) {
    return 'WhimBridgeIntegrationTests';
  }
  return null;
}

function xcodeSourceMemberships(project) {
  const objects = pbxObjects(project);
  const filePaths = new Map();
  const buildFiles = new Map();
  const sourcePhases = new Map();

  for (const [identifier, body] of objects) {
    const objectType = scalar(body, 'isa');
    if (objectType === 'PBXFileReference') {
      const filePath = scalar(body, 'path');
      if (filePath) {
        filePaths.set(
          identifier,
          path.posix.normalize(path.posix.join('ios', filePath.replaceAll('\\', '/'))),
        );
      }
    } else if (objectType === 'PBXBuildFile') {
      const fileReference = body.match(/fileRef\s*=\s*([A-Za-z0-9_]+)\s+\/\*/)?.[1];
      if (fileReference) buildFiles.set(identifier, fileReference);
    } else if (objectType === 'PBXSourcesBuildPhase') {
      sourcePhases.set(identifier, listIdentifiers(body, 'files'));
    }
  }

  const memberships = new Map();
  for (const body of objects.values()) {
    if (scalar(body, 'isa') !== 'PBXNativeTarget') continue;
    const targetName = scalar(body, 'name');
    if (!targetName) continue;
    for (const phaseIdentifier of listIdentifiers(body, 'buildPhases')) {
      for (const buildIdentifier of sourcePhases.get(phaseIdentifier) ?? []) {
        const filePath = filePaths.get(buildFiles.get(buildIdentifier));
        if (!filePath) continue;
        const targets = memberships.get(filePath) ?? [];
        targets.push(targetName);
        memberships.set(filePath, targets);
      }
    }
  }
  return memberships;
}

export async function checkRepository(root = process.cwd()) {
  const errors = [];
  const scannedRoots = ['src', 'packages', 'scripts'];
  const allFiles = (
    await Promise.all(scannedRoots.map((directory) => filesBelow(root, directory)))
  ).flat();
  const normalizedFiles = new Set(allFiles.map((file) => file.split(path.sep).join('/')));

  for (const file of normalizedFiles) {
    if (!/(?:\.integration)?\.test\.(?:[cm]?[jt]sx?|swift)$/.test(file)) continue;

    if (file.startsWith('src/iphone/app/')) {
      errors.push(`${file}: Expo Router route directories must remain test-free`);
    }

    const implementation = implementationFor(file);
    if (!normalizedFiles.has(implementation)) {
      errors.push(`${file}: expected adjacent implementation ${implementation}`);
    }
  }

  for (const file of normalizedFiles) {
    const parts = file.split('/');
    if (!['src', 'packages'].includes(parts[0])) continue;
    for (const directory of parts.slice(1, -1)) {
      if (genericArchitectureDirectories.has(directory.toLowerCase())) {
        errors.push(`${file}: generic architecture directory "${directory}" is forbidden`);
        break;
      }
    }
  }

  const packageRoot = 'packages/WhimCore/Sources/WhimCore/';
  const packageSwiftFiles = [...normalizedFiles]
    .filter((file) => file.startsWith(packageRoot) && file.endsWith('.swift'))
    .map((file) => file.slice(packageRoot.length));
  if (packageSwiftFiles.length > 0) {
    let manifest;
    try {
      manifest = await readFile(path.join(root, 'packages/WhimCore/Package.swift'), 'utf8');
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      errors.push('packages/WhimCore/Package.swift: missing explicit SwiftPM source lists');
    }

    if (manifest) {
      const lists = {
        productionSources: sourceList(manifest, 'productionSources'),
        unitTestSources: sourceList(manifest, 'unitTestSources'),
        integrationTestSources: sourceList(manifest, 'integrationTestSources'),
      };
      for (const [name, sources] of Object.entries(lists)) {
        if (!sources) errors.push(`packages/WhimCore/Package.swift: missing ${name}`);
      }

      if (Object.values(lists).every(Boolean)) {
        for (const swiftFile of packageSwiftFiles) {
          const expectedList = swiftFile.endsWith('.integration.test.swift')
            ? 'integrationTestSources'
            : swiftFile.endsWith('.test.swift')
              ? 'unitTestSources'
              : 'productionSources';
          if (!lists[expectedList].includes(swiftFile)) {
            errors.push(`${swiftFile}: missing from ${expectedList}`);
          }
          for (const [name, sources] of Object.entries(lists)) {
            if (name !== expectedList && sources.includes(swiftFile)) {
              errors.push(`${swiftFile}: must not appear in ${name}`);
            }
          }
        }
      }
    }
  }

  let xcodeProject;
  try {
    xcodeProject = await readFile(path.join(root, 'ios/whim.xcodeproj/project.pbxproj'), 'utf8');
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }

  if (xcodeProject) {
    const memberships = xcodeSourceMemberships(xcodeProject);
    for (const file of normalizedFiles) {
      const expectedTarget = intendedXcodeTarget(file);
      if (!expectedTarget) continue;
      const actualTargets = memberships.get(file) ?? [];
      if (!actualTargets.includes(expectedTarget)) {
        errors.push(`${file}: missing from ${expectedTarget}`);
      }
      for (const actualTarget of actualTargets) {
        if (actualTarget === expectedTarget) continue;
        const message = file.endsWith('.test.swift') && !actualTarget.endsWith('Tests')
          ? `${file}: must not compile in ${actualTarget}`
          : `${file}: expected only ${expectedTarget}, found ${actualTarget}`;
        errors.push(message);
      }
    }
  }

  return errors.sort();
}

async function main() {
  const errors = await checkRepository();
  if (errors.length > 0) {
    console.error(['Test colocation check failed:', ...errors.map((error) => `- ${error}`)].join('\n'));
    process.exitCode = 1;
  } else {
    console.log('Test colocation check passed.');
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
