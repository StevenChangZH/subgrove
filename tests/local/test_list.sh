#!/usr/bin/env bash
# Tests for `subgrove list` and the dispatcher.
set -eo pipefail

. "$(dirname "$0")/../lib/assert.sh"
. "$(dirname "$0")/../lib/fixture_local.sh"

# --- case: list shows worktrees ---
mkfixture_local list_basic
cd "$FIXTURE_SUPER"
./subgrove new feat-a >out 2>&1
./subgrove new feat-b >out 2>&1
./subgrove list > out 2>&1
# Pin the branch annotation `git worktree list` emits — confirms both
# feat branches are listed (not just that the names appear somewhere).
assert_grep out "\[feat/feat-a\]"
assert_grep out "\[feat/feat-b\]"
cleanup_fixture

# --- case: ls alias ---
mkfixture_local list_alias
cd "$FIXTURE_SUPER"
./subgrove new feat-a >out 2>&1
./subgrove ls > out 2>&1
assert_grep out "feat-a"
cleanup_fixture

# --- case: subgrove (no args) → prints usage, exit 0 ---
# subcmd defaults to "help", so no-args is equivalent to `help`.
mkfixture_local list_no_args
cd "$FIXTURE_SUPER"
./subgrove > out 2>&1
assert_grep out "subgrove new"
cleanup_fixture

# --- case: explicit help ---
mkfixture_local list_help
cd "$FIXTURE_SUPER"
./subgrove help > out 2>&1
assert_grep out "subgrove new"
cleanup_fixture

# --- case: bogus subcommand → exit non-zero AND prints usage ---
mkfixture_local list_bogus
cd "$FIXTURE_SUPER"
if ./subgrove bogus-cmd-xyz >out 2>&1; then
    fail "expected bogus subcommand to exit non-zero"
fi
# Per the dispatcher's `*) usage; exit 1`, the usage text is printed.
assert_grep out "subgrove new"
cleanup_fixture

# --- case: rm alias ---
mkfixture_local list_rm_alias
cd "$FIXTURE_SUPER"
./subgrove new feat-a >out 2>&1
./subgrove rm feat-a >out 2>&1
assert_file_absent .worktree/feat-a
cleanup_fixture

# --- case: -h short flag prints usage ---
mkfixture_local list_h_short
cd "$FIXTURE_SUPER"
./subgrove -h > out 2>&1
assert_grep out "subgrove new"
cleanup_fixture

# --- case: --help long flag prints usage ---
mkfixture_local list_help_long
cd "$FIXTURE_SUPER"
./subgrove --help > out 2>&1
assert_grep out "subgrove new"
cleanup_fixture
