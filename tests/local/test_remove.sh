#!/usr/bin/env bash
# Tests for `subgrove remove`.
set -eo pipefail

. "$(dirname "$0")/../lib/assert.sh"
. "$(dirname "$0")/../lib/fixture_local.sh"

# --- case: golden ---
mkfixture_local remove_golden
cd "$FIXTURE_SUPER"
./subgrove new feat-x >out 2>&1
./subgrove remove feat-x >out 2>&1
assert_file_absent .worktree/feat-x
# parent branch is retained
assert_branch_at . feat/feat-x
cleanup_fixture

# --- case: dirty parent worktree refused ---
mkfixture_local remove_dirty_parent
cd "$FIXTURE_SUPER"
./subgrove new feat-y >out 2>&1
echo "uncommitted" >> .worktree/feat-y/README
if ./subgrove remove feat-y >out 2>&1; then
    fail "expected remove to refuse on dirty parent"
fi
assert_file_exists .worktree/feat-y
cleanup_fixture

# --- case: dirty touched submodule refused ---
mkfixture_local remove_dirty_touched
cd "$FIXTURE_SUPER"
./subgrove new feat-y >out 2>&1
echo "uncommitted" >> .worktree/feat-y/sm-a/README
if ./subgrove remove feat-y >out 2>&1; then
    fail "expected remove to refuse on dirty submodule"
fi
assert_file_exists .worktree/feat-y
cleanup_fixture

# --- case: dirty UN-touched submodule refused ---
# touch=sm-a means sm-b has no feat branch but IS initialised. A dirty sm-b
# must still block remove — otherwise rm -rf would silently destroy work.
mkfixture_local remove_dirty_untouched
cd "$FIXTURE_SUPER"
./subgrove new feat-y touch=sm-a >out 2>&1
echo "uncommitted" >> .worktree/feat-y/sm-b/README
if ./subgrove remove feat-y >out 2>&1; then
    fail "expected remove to refuse on dirty UN-touched submodule"
fi
assert_file_exists .worktree/feat-y
cleanup_fixture

# --- case: -f overrides dirty ---
mkfixture_local remove_force
cd "$FIXTURE_SUPER"
./subgrove new feat-y >out 2>&1
echo "uncommitted" >> .worktree/feat-y/README
./subgrove remove feat-y -f >out 2>&1
assert_file_absent .worktree/feat-y
cleanup_fixture

# --- case: --force alias ---
mkfixture_local remove_force_long
cd "$FIXTURE_SUPER"
./subgrove new feat-a >out 2>&1
echo "uncommitted" >> .worktree/feat-a/README
./subgrove remove feat-a --force >out 2>&1
assert_file_absent .worktree/feat-a
cleanup_fixture

# --- case: force=true alias ---
mkfixture_local remove_force_kv
cd "$FIXTURE_SUPER"
./subgrove new feat-b >out 2>&1
echo "uncommitted" >> .worktree/feat-b/README
./subgrove remove feat-b force=true >out 2>&1
assert_file_absent .worktree/feat-b
cleanup_fixture

# --- case: nonexistent name refused ---
mkfixture_local remove_nonexistent
cd "$FIXTURE_SUPER"
if ./subgrove remove never-existed >out 2>&1; then
    fail "expected remove to refuse on nonexistent name"
fi
cleanup_fixture

# --- case: removing one worktree leaves siblings untouched ---
mkfixture_local remove_one_of_many
cd "$FIXTURE_SUPER"
./subgrove new feat-a >out 2>&1
./subgrove new feat-b >out 2>&1
./subgrove remove feat-a >out 2>&1
assert_file_absent .worktree/feat-a
assert_file_exists .worktree/feat-b
# Branches retained for both (per lifecycle.md).
assert_branch_at . feat/feat-a
assert_branch_at . feat/feat-b
cleanup_fixture

# --- case: re-create same name after remove refused; succeeds after branch deletion ---
# Per lifecycle.md, `remove` retains branches. So `new feat-x` after
# `remove feat-x` should hit the "branch already exists" check. The user
# must delete the branch manually first.
mkfixture_local remove_then_recreate
cd "$FIXTURE_SUPER"
./subgrove new feat-x >out 2>&1
./subgrove remove feat-x >out 2>&1
if ./subgrove new feat-x >out 2>&1; then
    fail "expected new to refuse re-create when branch is retained"
fi
assert_grep out "already exists"
git branch -D feat/feat-x
./subgrove new feat-x >out 2>&1
assert_file_exists .worktree/feat-x
cleanup_fixture
