#!/bin/bash
# Run the repository-pinned SwiftFormat binary.
set -euo pipefail

readonly SWIFTFORMAT_VERSION="0.62.1"
readonly SWIFTFORMAT_SHA256="7cb1cb1fae04932047c7015441c543848e8e60e1572d808d080e0a1f1661114a"
readonly SWIFTFORMAT_URL="https://github.com/nicklockwood/SwiftFormat/releases/download/${SWIFTFORMAT_VERSION}/swiftformat.zip"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cache_dir="${SWIFTFORMAT_CACHE_DIR:-${repo_root}/.build/tools/swiftformat/${SWIFTFORMAT_VERSION}}"
cached_binary="${cache_dir}/swiftformat"

installed_binary="$(command -v swiftformat || true)"
if [[ -n "$installed_binary" ]] \
    && [[ "$("$installed_binary" --version)" == "$SWIFTFORMAT_VERSION" ]]; then
    exec "$installed_binary" "$@"
fi

if [[ -x "$cached_binary" ]] \
    && [[ "$("$cached_binary" --version)" == "$SWIFTFORMAT_VERSION" ]]; then
    exec "$cached_binary" "$@"
fi

echo "Downloading SwiftFormat ${SWIFTFORMAT_VERSION}..." >&2
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/dahlia-swiftformat.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT

archive_path="${temporary_dir}/swiftformat.zip"
curl --fail --location --silent --show-error "$SWIFTFORMAT_URL" --output "$archive_path"

actual_sha256="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
if [[ "$actual_sha256" != "$SWIFTFORMAT_SHA256" ]]; then
    echo "error: SwiftFormat SHA-256 mismatch" >&2
    echo "expected: $SWIFTFORMAT_SHA256" >&2
    echo "actual:   $actual_sha256" >&2
    exit 1
fi

unzip -q "$archive_path" -d "$temporary_dir"
mkdir -p "$cache_dir"
cp "${temporary_dir}/swiftformat" "$cached_binary"
chmod +x "$cached_binary"

"$cached_binary" "$@"
