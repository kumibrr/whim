/// <reference types="node" />
import { execFileSync } from 'node:child_process';
import path from 'node:path';

it('registers ExpoWhim in the real Apple Expo module resolver', () => {
  const root = path.resolve(__dirname, '../../../..');
  const output = execFileSync(process.execPath, [path.join(root, 'node_modules/expo-modules-autolinking/bin/expo-modules-autolinking.js'), 'resolve', '--platform', 'apple', '--json'], { cwd: root, encoding: 'utf8' });
  const resolved = JSON.parse(output);
  const module = resolved.modules.find((value: { packageName: string }) => value.packageName === '@whim/expo-whim');
  expect(module?.modules.map((value: { class: string }) => value.class)).toEqual(['ExpoWhimModule']);
});
