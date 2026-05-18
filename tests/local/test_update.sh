#!/usr/bin/env bash
# Tests for `subgrove update`.
#
# Note: super has no `origin` configured in the local fixture. cmd_update's
# parent-level fetch falls through with a warn, but each main-worktree
# submodule HAS its own file:// origin (pointing at the sibling sm-X repo
# under $FIXTURE_ROOT). Simulating "someone pushed upstream" is just a
# direct commit in the sibling — subgrove's fetch picks it up via file://.
set -eo pipefail

. "$(dirname "$0")/../lib/assert.sh"
. "$(dirname "$0")/../lib/fixture_local.sh"

# --- case: happy path — peer catches up to new origin/main ---
mkfixture_local update_happy
cd "$FIXTURE_SUPER"
./subgrove new feat-y >out 2>&1
# Move sibling sm-a's main forward; subgrove will fetch this into main
# super's sm-a, then propagate via the _update_sync sentinel.
commit_one "$FIXTURE_ROOT/sm-a" "upstream change"
new_main="$(git -C "$FIXTURE_ROOT/sm-a" rev-parse main)"
./subgrove update feat-y >out 2>&1
assert_branch_at .worktree/feat-y/sm-a main "$new_main"
cleanup_fixture

# --- case: _update_sync sentinel cleaned up on success ---
mkfixture_local update_sentinel_clean
cd "$FIXTURE_SUPER"
./subgrove new feat-y >out 2>&1
./subgrove update feat-y >out 2>&1
if git -C sm-a rev-parse --verify --quiet refs/heads/_update_sync >/dev/null 2>&1; then
    fail "_update_sync ref leaked after update (clean run)"
fi
if git -C sm-b rev-parse --verify --quiet refs/heads/_update_sync >/dev/null 2>&1; then
    fail "_update_sync ref leaked after update (clean run)"
fi
cleanup_fixture

# --- case: pre-existing _update_sync ref cleaned up ---
mkfixture_local update_sentinel_pre
cd "$FIXTURE_SUPER"
./subgrove new feat-y >out 2>&1
git -C sm-a update-ref refs/heads/_update_sync "$(git -C sm-a rev-parse main)"
./subgrove update feat-y >out 2>&1
if git -C sm-a rev-parse --verify --quiet refs/heads/_update_sync >/dev/null 2>&1; then
    fail "_update_sync ref leaked after update (pre-existing case)"
fi
cleanup_fixture

# --- case: peer with main checked out → skipped ---
mkfixture_local update_peer_main_co
cd "$FIXTURE_SUPER"
./subgrove new feat-y >out 2>&1
( cd .worktree/feat-y/sm-a && git checkout --quiet main )
peer_main_before="$(git -C .worktree/feat-y/sm-a rev-parse main)"
commit_one "$FIXTURE_ROOT/sm-a" "upstream change"
./subgrove update feat-y >out 2>&1
assert_grep out "main checked out"
peer_main_after="$(git -C .worktree/feat-y/sm-a rev-parse main)"
assert_eq "$peer_main_before" "$peer_main_after"
cleanup_fixture

# --- case: peer's main diverged → skipped ---
mkfixture_local update_peer_diverged
cd "$FIXTURE_SUPER"
./subgrove new feat-y >out 2>&1
(
    cd .worktree/feat-y/sm-a
    new_sha="$(git commit-tree -m diverge -p main "$(git rev-parse main^{tree})")"
    git update-ref refs/heads/main "$new_sha"
)
commit_one "$FIXTURE_ROOT/sm-a" "upstream change"
./subgrove update feat-y >out 2>&1
assert_grep out "diverged"
cleanup_fixture

# --- case: no refs/remotes/origin/main → skipped with warn ---
# Strip origin from main super's submodules to simulate "user didn't
# configure a remote on the submodules either." cmd_update should warn
# and skip rather than fail.
mkfixture_local update_no_origin
cd "$FIXTURE_SUPER"
git -C sm-a remote remove origin
git -C sm-b remote remove origin
./subgrove new feat-y >out 2>&1
./subgrove update feat-y >out 2>&1
assert_grep out "no refs/remotes/origin/main"
cleanup_fixture

# --- case: doesn't require clean state ---
mkfixture_local update_dirty_ok
cd "$FIXTURE_SUPER"
./subgrove new feat-y >out 2>&1
echo "dirty" >> .worktree/feat-y/sm-a/README
./subgrove update feat-y >out 2>&1
cleanup_fixture

# --- case: nonexistent name refused ---
mkfixture_local update_nonexistent
cd "$FIXTURE_SUPER"
if ./subgrove update never-existed >out 2>&1; then
    fail "expected update to fail on nonexistent name"
fi
cleanup_fixture

# --- case: multiple submodules update in one run ---
# Both sibling sm-a and sm-b get new upstream commits. After update, both
# peer submodules' main refs should advance independently.
mkfixture_local update_multi_sm
cd "$FIXTURE_SUPER"
./subgrove new feat-y >out 2>&1
commit_one "$FIXTURE_ROOT/sm-a" "upstream sm-a"
commit_one "$FIXTURE_ROOT/sm-b" "upstream sm-b"
new_sm_a="$(git -C "$FIXTURE_ROOT/sm-a" rev-parse main)"
new_sm_b="$(git -C "$FIXTURE_ROOT/sm-b" rev-parse main)"
./subgrove update feat-y >out 2>&1
assert_branch_at .worktree/feat-y/sm-a main "$new_sm_a"
assert_branch_at .worktree/feat-y/sm-b main "$new_sm_b"
cleanup_fixture

# --- case: dirty main super doesn't block update ---
# cmd_update is ref-only and doesn't `require_clean`. Dirty state in the
# main super (parent + both submodules) should not prevent update.
mkfixture_local update_dirty_super_ok
cd "$FIXTURE_SUPER"
./subgrove new feat-y >out 2>&1
echo "dirty parent" >> README
echo "dirty sm-a" >> sm-a/README
echo "dirty sm-b" >> sm-b/README
commit_one "$FIXTURE_ROOT/sm-a" "upstream sm-a"
new_main="$(git -C "$FIXTURE_ROOT/sm-a" rev-parse main)"
./subgrove update feat-y >out 2>&1
assert_branch_at .worktree/feat-y/sm-a main "$new_main"
cleanup_fixture
