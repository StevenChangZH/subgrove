#!/usr/bin/env bash
# Tests for `subgrove list` and the dispatcher on a no-submodule remote
# fixture.
#
# Companion to tests/local-no-sm/test_list.sh. The dispatcher and `list`
# are independent of origin, but the tier exercises them once on a
# remote-cloned no-sm super to catch any future code path that branches
# on clone-vs-init state (e.g., help text that probes refs/remotes/).
set -eo pipefail

. "$(dirname "$0")/../lib/assert.sh"
. "$(dirname "$0")/../lib/fixture_remote_no_sm.sh"

# --- case: list shows worktrees ---
mkfixture_remote_no_sm list_basic
cd "$FIXTURE_SUPER"
./subgrove new feat-a >/dev/null 2>&1
register_feature_branch_no_sm feat/feat-a
./subgrove new feat-b >/dev/null 2>&1
register_feature_branch_no_sm feat/feat-b
./subgrove list > out 2>&1
assert_grep out "\[feat/feat-a\]"
assert_grep out "\[feat/feat-b\]"
cleanup_fixture_remote_no_sm

# --- case: ls alias ---
mkfixture_remote_no_sm list_alias
cd "$FIXTURE_SUPER"
./subgrove new feat-a >/dev/null 2>&1
register_feature_branch_no_sm feat/feat-a
./subgrove ls > out 2>&1
# Pin the branch annotation `git worktree list` emits — confirms the
# alias dispatches to cmd_list, not e.g. a `ls` that prints raw paths.
assert_grep out "\[feat/feat-a\]"
cleanup_fixture_remote_no_sm

# --- case: subgrove (no args) → prints usage, exit 0 ---
mkfixture_remote_no_sm list_no_args
cd "$FIXTURE_SUPER"
./subgrove > out 2>&1
assert_grep out "subgrove new"
cleanup_fixture_remote_no_sm

# --- case: explicit help ---
mkfixture_remote_no_sm list_help
cd "$FIXTURE_SUPER"
./subgrove help > out 2>&1
assert_grep out "subgrove new"
cleanup_fixture_remote_no_sm

# --- case: bogus subcommand → exit non-zero AND prints usage ---
mkfixture_remote_no_sm list_bogus
cd "$FIXTURE_SUPER"
if ./subgrove bogus-cmd-xyz >out 2>&1; then
    fail "expected bogus subcommand to exit non-zero"
fi
assert_grep out "subgrove new"
cleanup_fixture_remote_no_sm

# --- case: rm alias ---
mkfixture_remote_no_sm list_rm_alias
cd "$FIXTURE_SUPER"
./subgrove new feat-a >/dev/null 2>&1
register_feature_branch_no_sm feat/feat-a
# Prove the precondition explicitly: the worktree dir DOES exist after
# `new`. Without this, a regression where `new` silently no-ops + `rm`
# also silently no-ops would pass assert_file_absent by accident.
assert_file_exists .worktree/feat-a
./subgrove rm feat-a >out 2>&1
assert_file_absent .worktree/feat-a
cleanup_fixture_remote_no_sm

# --- case: -h short flag prints usage ---
mkfixture_remote_no_sm list_h_short
cd "$FIXTURE_SUPER"
./subgrove -h > out 2>&1
assert_grep out "subgrove new"
cleanup_fixture_remote_no_sm

# --- case: --help long flag prints usage ---
mkfixture_remote_no_sm list_help_long
cd "$FIXTURE_SUPER"
./subgrove --help > out 2>&1
assert_grep out "subgrove new"
cleanup_fixture_remote_no_sm
