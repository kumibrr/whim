import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

// Xcode's global Custom build location overrides -derivedDataPath, so scripts that read
// built products must pass the explicit SYMROOT/OBJROOT from xcode-build-locations.sh.
export async function checkXcodeBuildLocations(root = process.cwd()) {
  const errors = [];
  const scripts = (await readdir(join(root, 'scripts'))).filter(file => file.endsWith('.sh')).sort();
  for (const script of scripts) {
    const lines = (await readFile(join(root, 'scripts', script), 'utf8')).split('\n');
    for (let start = 0; start < lines.length; start++) {
      let end = start;
      while (lines[end].trimEnd().endsWith('\\') && end + 1 < lines.length) end++;
      const command = lines.slice(start, end + 1).join(' ');
      if (/^\s*xcodebuild\b.*\s(?:build|test)\s/.test(`${command} `) && !command.includes('"${whim_xcode_build_locations[@]}"')) {
        errors.push(`scripts/${script}:${start + 1}: xcodebuild must pass "\${whim_xcode_build_locations[@]}"`);
      }
      start = end;
    }
  }
  return errors;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const errors = await checkXcodeBuildLocations();
  for (const error of errors) console.error(error);
  process.exit(errors.length ? 1 : 0);
}
