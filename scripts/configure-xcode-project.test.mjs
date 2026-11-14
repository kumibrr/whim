import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, mkdir, copyFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
const exec = promisify(execFile);

test('project regeneration restores the optimized benchmark target and scheme while preserving target-specific DEBUG flags', async t => {
  try { await exec('ruby', ['-rxcodeproj', '-e', '']); }
  catch { t.skip('Requires the xcodeproj gem used by project regeneration'); return; }
  const root = await mkdtemp(join(tmpdir(), 'whim-project-generation-'));
  t.after(() => rm(root, { force: true, recursive: true }));
  for (const path of ['scripts/configure-xcode-project.rb', 'Package.swift', 'ios/package.json', 'ios/whim.xcodeproj/project.pbxproj']) {
    await mkdir(join(root, path, '..'), { recursive: true });
    await copyFile(new URL(`../${path}`, import.meta.url), join(root, path));
  }
  await exec('ruby', ['-rxcodeproj', '-e', `p=Xcodeproj::Project.open(ARGV[0]); p.targets.select { |t| ['WhimPerformanceTests','WhimBenchmarkHistory'].include?(t.name) }.each(&:remove_from_project); ([p]+p.targets).each { |t| t.build_configurations.select { |c| c.name=='DebugBenchmark' }.each { |c| t.build_configuration_list.build_configurations.delete(c); c.remove_from_project } }; p.save`, join(root, 'ios/whim.xcodeproj')]);
  await exec('ruby', [join(root, 'scripts/configure-xcode-project.rb')]);
  const inspect = `p=Xcodeproj::Project.open(ARGV[0]); t=p.targets.find { |t| t.name=='WhimPerformanceTests' }; abort 'Missing benchmark target' unless t; c=p.targets.find { |t| t.name=='WhimLiveActivity' }.build_settings('DebugBenchmark'); puts JSON.generate({optimization: c['SWIFT_OPTIMIZATION_LEVEL'], flags: c['SWIFT_ACTIVE_COMPILATION_CONDITIONS'], inputs: t.shell_script_build_phases.map(&:shell_script), sources: t.source_build_phase.files_references.map(&:path), scheme: File.read(File.join(ARGV[0],'xcshareddata/xcschemes/WhimPerformanceTests.xcscheme'))})`;
  const result = JSON.parse((await exec('ruby', ['-rxcodeproj', '-rjson', '-e', inspect, join(root, 'ios/whim.xcodeproj')])).stdout);
  assert.equal(result.optimization, '-O');
  assert.match(result.flags, /WHIM_WIDGET_EXTENSION/); assert.match(result.flags, /DEBUG/);
  assert.ok(result.inputs.some(s => s.includes('benchmark-input.mjs')));
  assert.ok(result.sources.includes('../e2e/iphone/Performance.e2e.test.swift'));
  assert.match(result.scheme, /buildConfiguration = "DebugBenchmark"/);
});
