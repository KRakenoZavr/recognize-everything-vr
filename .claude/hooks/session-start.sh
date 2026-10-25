#!/bin/bash
# Prepares Claude Code cloud sessions for this Rust project.
set -euo pipefail

# Only run in cloud sessions; local machines manage their own toolchains.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

if command -v rustup >/dev/null 2>&1; then
  rustup component add rustfmt clippy >/dev/null 2>&1
  # Android arm64 target for cross-compiling the Quest 3 / 3S client crates.
  rustup target add aarch64-linux-android >/dev/null 2>&1
fi

# Pre-fetch dependencies once a Cargo workspace exists.
if [ -f Cargo.toml ]; then
  cargo fetch
fi
