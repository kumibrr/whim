import assert from 'node:assert/strict';
import test from 'node:test';

import { selectCompatibleRuntimes } from './select-apple-runtimes.mjs';

function runtime(family, version, isAvailable = true) {
  return {
    identifier: `com.apple.CoreSimulator.SimRuntime.${family}-${version.replaceAll('.', '-')}`,
    isAvailable,
    version,
  };
}

test('selects the newest compatible supported iOS and watchOS pair', () => {
  const selection = selectCompatibleRuntimes([
    runtime('iOS', '17.5'),
    runtime('iOS', '18.6'),
    runtime('iOS', '26.0'),
    runtime('watchOS', '10.6'),
    runtime('watchOS', '26.0'),
    runtime('watchOS', '27.0'),
  ]);

  assert.equal(selection.ios.version, '26.0');
  assert.equal(selection.watch.version, '26.0');
});

test('supports the pre-renumbering iOS 18 and watchOS 11 pairing', () => {
  const selection = selectCompatibleRuntimes([
    runtime('iOS', '18.0'),
    runtime('watchOS', '11.0'),
  ]);

  assert.equal(selection.ios.version, '18.0');
  assert.equal(selection.watch.version, '11.0');
});

test('ignores unavailable runtimes and fails clearly without a supported pair', () => {
  assert.throws(
    () =>
      selectCompatibleRuntimes([
        runtime('iOS', '27.0', false),
        runtime('iOS', '17.5'),
        runtime('watchOS', '27.0'),
        runtime('watchOS', '10.6'),
      ]),
    /No compatible simulator pair.*iOS 18.*watchOS 11/,
  );
});
