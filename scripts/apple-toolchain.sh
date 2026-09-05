#!/usr/bin/env bash

if [[ "$(uname -s)" != "Darwin" ]]; then
  return 0 2>/dev/null || exit 0
fi

if [[ -n "${DEVELOPER_DIR:-}" && -x "${DEVELOPER_DIR}/usr/bin/xcodebuild" ]]; then
  export DEVELOPER_DIR
  return 0 2>/dev/null || exit 0
fi

for whim_xcode in \
  /Applications/Xcode.app/Contents/Developer \
  /Applications/Xcode-beta.app/Contents/Developer \
  "$(xcode-select -p 2>/dev/null || true)"; do
  if [[ -n "$whim_xcode" && -x "$whim_xcode/usr/bin/xcodebuild" ]]; then
    export DEVELOPER_DIR="$whim_xcode"
    return 0 2>/dev/null || exit 0
  fi
done

echo "Whim requires a complete Xcode installation." >&2
return 1 2>/dev/null || exit 1
