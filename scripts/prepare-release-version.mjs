import { spawn } from 'node:child_process';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { syncAppVersion } from './sync-app-version.mjs';

export function runCommand(command, args, { cwd, capture = false, env } = {}) {
  return new Promise((resolveCommand, reject) => {
    const child = spawn(command, args, { cwd, env, stdio: ['ignore', capture ? 'pipe' : 'inherit', 'inherit'] });
    let stdout = '';
    child.stdout?.on('data', data => { stdout += data; });
    child.on('error', reject);
    child.on('close', code => code === 0 ? resolveCommand(stdout) : reject(new Error(`${command} ${args.join(' ')} failed (exit ${code}).`)));
  });
}

export async function prepareReleaseVersion(root = process.cwd(), run = runCommand) {
  await run(process.execPath, [join(root, 'node_modules/@changesets/cli/bin.js'), 'version'], { cwd: root });
  const version = await syncAppVersion(root);
  await run('npm', ['install', '--package-lock-only', '--ignore-scripts', '--no-audit', '--no-fund'], { cwd: root });
  return version;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { console.log(`Prepared app version ${await prepareReleaseVersion()}.`); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
