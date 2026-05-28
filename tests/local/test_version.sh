#!/usr/bin/env bash
# `subgrove --version` and `subgrove version` report the version and work
# anywhere — no git repo required. They must NOT trigger repo discovery, so
# the test runs them from a dir outside any git repo.
set -eo pipefail

. "$(dirname "$0")/../lib/assert.sh"
SUBGROVE_REPO_ROOT="${SUBGROVE_REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
sg="$SUBGROVE_REPO_ROOT/subgrove"

outside="$(mktemp -d "${TMPDIR:-/tmp}/subgrove-ver.XXXXXX")"
trap 'rm -rf "$outside"' EXIT
cd "$outside"

if ! "$sg" --version >out 2>&1; then
    echo "--- out ---"; cat out
    fail "--version exited non-zero"
fi
assert_grep out "subgrove [0-9]+\.[0-9]+\.[0-9]+"

if ! "$sg" version >out 2>&1; then
    echo "--- out ---"; cat out
    fail "version subcommand exited non-zero"
fi
assert_grep out "subgrove [0-9]+\.[0-9]+\.[0-9]+"

# --- version is single-sourced from subgrove's VERSION ---
# flake.nix `version` and packaging/aur/PKGBUILD `pkgver` MUST match it; bump
# all three together. This guards the drift that once let the PKGBUILD say
# 0.0.0 while the script said 0.1.0. (`out` still holds the `version` output.)
ver="$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$sg")"
[[ -n "$ver" ]] || fail "could not read VERSION= from $sg"
assert_grep out "subgrove $ver"
flake_ver="$(sed -n 's/.*version = "\([0-9][0-9.]*\)".*/\1/p' "$SUBGROVE_REPO_ROOT/flake.nix" | head -n1)"
pkg_ver="$(sed -n 's/^pkgver=\(.*\)/\1/p' "$SUBGROVE_REPO_ROOT/packaging/aur/PKGBUILD")"
assert_eq "$ver" "$flake_ver" "flake.nix version must match subgrove VERSION ($ver)"
assert_eq "$ver" "$pkg_ver"   "PKGBUILD pkgver must match subgrove VERSION ($ver)"

echo "PASS"
