#!/usr/bin/env bash
set -euo pipefail

# This script builds the native Bracket binary and stages the npm package for local publication.
# It assumes you have cargo, node, pnpm, and python3 installed.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_RS_DIR="${REPO_ROOT}/codex-rs"
CODEX_CLI_DIR="${REPO_ROOT}/codex-cli"
SCRIPTS_DIR="${REPO_ROOT}/scripts"
DIST_DIR="${REPO_ROOT}/dist"

VERSION="${1:-0.1.0}"
PROFILE="${2:-release}"

echo "Building Bracket version ${VERSION} (${PROFILE})..."

# 1. Build the native binary
cd "${CODEX_RS_DIR}"
CARGO="$HOME/.cargo/bin/cargo"
if [ "${PROFILE}" == "release" ]; then
    $CARGO build --release --bin bracket
    BINARY_PATH="target/release/bracket"
else
    $CARGO build --bin bracket
    BINARY_PATH="target/debug/bracket"
fi

# 2. Prepare vendor directory structure for the current platform
RUSTC="$HOME/.cargo/bin/rustc"
TARGET_TRIPLE=$($RUSTC -vV | sed -n 's/^host: //p')
echo "Detected target triple: ${TARGET_TRIPLE}"

VENDOR_STAGE="${DIST_DIR}/vendor_stage"
mkdir -p "${VENDOR_STAGE}/${TARGET_TRIPLE}/bracket"
cp "${BINARY_PATH}" "${VENDOR_STAGE}/${TARGET_TRIPLE}/bracket/bracket"

# Also copy rg (ripgrep) if it exists in a path directory, otherwise build_npm_package will complain
# For a local dev build, we can just use a dummy or skip if not strictly needed
mkdir -p "${VENDOR_STAGE}/${TARGET_TRIPLE}/path"
if command -v rg >/dev/null 2>&1; then
    cp "$(command -v rg)" "${VENDOR_STAGE}/${TARGET_TRIPLE}/path/rg"
else
    echo "Using dummy rg"
    echo "#!/bin/sh" > "${VENDOR_STAGE}/${TARGET_TRIPLE}/path/rg"
    chmod +x "${VENDOR_STAGE}/${TARGET_TRIPLE}/path/rg"
fi

# 3. Copy sandbox binary if it exists
if [ -f "target/$( [ "${PROFILE}" == "release" ] && echo "release" || echo "debug" )/bracket-linux-sandbox" ]; then
    cp "target/$( [ "${PROFILE}" == "release" ] && echo "release" || echo "debug" )/bracket-linux-sandbox" "${VENDOR_STAGE}/${TARGET_TRIPLE}/bracket/bracket-linux-sandbox"
fi

# 4. Stage the npm package
# Note: stage_npm_packages.py usually downloads from GHA, but we'll use build_npm_package.py directly
# to bundle our local binary.

STAGING_DIR="${DIST_DIR}/npm_stage"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

python3 "${CODEX_CLI_DIR}/scripts/build_npm_package.py" \
    --package bracket \
    --version "${VERSION}" \
    --staging-dir "${STAGING_DIR}" \
    --vendor-src "${VENDOR_STAGE}" \
    --pack-output "${DIST_DIR}/bracket-${VERSION}.tgz"

echo "--------------------------------------------------"
echo "Package staged in: ${STAGING_DIR}"
echo "Tarball created at: ${DIST_DIR}/bracket-${VERSION}.tgz"
echo ""
echo "To publish locally (dry run):"
echo "  cd ${STAGING_DIR} && npm publish --dry-run"
echo ""
echo "To install your local build globally:"
echo "  npm install -g ${DIST_DIR}/bracket-${VERSION}.tgz"
echo "--------------------------------------------------"
