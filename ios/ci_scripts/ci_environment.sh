#!/bin/bash
# Sourced by every hook: action machines and hook shell environments are isolated.
set -euo pipefail
export HOMEBREW_NO_AUTO_UPDATE=1
whim_brew_prefix="$(brew --prefix)"
export PATH="$whim_brew_prefix/opt/node@24/bin:$PATH"
if [[ ! -x "$whim_brew_prefix/opt/node@24/bin/node" ]]; then
  brew install node@24
fi
node -e 'if (Number(process.versions.node.split(".")[0]) !== 24) process.exit(1)'

whim_setup_test_dependencies() {
  if [[ ! -d "$whim_brew_prefix/opt/openjdk@17" ]]; then
    brew install openjdk@17
  fi
  export JAVA_HOME="$whim_brew_prefix/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
  export PATH="$JAVA_HOME/bin:$HOME/.maestro/bin:$PATH"
  java -version
  export MAESTRO_CLI_NO_ANALYTICS=1
  export MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true
  local whim_maestro_version=2.10.0
  local whim_maestro_sha=29b675e10cc12080e445e9bfb2e2b4e4dfb9c0f2e30d5884120d258b5e1cd991
  local whim_download
  whim_download="$(mktemp -d "${TMPDIR:-/tmp}/whim-maestro.XXXXXX")"
  curl --fail --location --silent --show-error \
    "https://github.com/mobile-dev-inc/Maestro/releases/download/cli-$whim_maestro_version/maestro.zip" \
    --output "$whim_download/maestro.zip"
  echo "$whim_maestro_sha  $whim_download/maestro.zip" | shasum -a 256 --check
  unzip -q "$whim_download/maestro.zip" -d "$whim_download/extracted"
  mkdir -p "$HOME/.maestro"
  cp -R "$whim_download/extracted/maestro/." "$HOME/.maestro/"
  rm -rf "$whim_download"
  maestro --version
}
