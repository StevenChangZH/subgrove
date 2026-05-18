#!/usr/bin/env bash
# Tests for `subgrove merge`.
#
# Note: `merge push=true` paths are NOT exercised here. The local fixture's
# super has no `origin` configured (since it's never cloned from anywhere),
# so push has nothing to target. push=true is covered by the remote tests.
set -eo pipefail

. "$(dirname "$0")/../lib/assert.sh"
. "$(dirname "$0")/../lib/fixture_local.sh"

# --- case: golden ---
mkfixture_local merge_golden
cd "$FIXTURE_SUPER"
./subgrove new feat-x >out 2>&1
commit_one .worktree/feat-x/sm-a "sm-a change"
commit_one .worktree/feat-x/sm-b "sm-b change"
( cd .worktree/feat-x && git add -A && git commit --quiet -m "bump sm SHAs" )

feat_super="$(git -C .worktree/feat-x rev-parse feat/feat-x)"
feat_a="$(git -C .worktree/feat-x/sm-a rev-parse feat/feat-x)"
feat_b="$(git -C .worktree/feat-x/sm-b rev-parse feat/feat-x)"

./subgrove merge feat-x >out 2>&1
assert_branch_at . main "$feat_super"
assert_branch_at sm-a main "$feat_a"
assert_branch_at sm-b main "$feat_b"
# worktree retained
assert_file_exists .worktree/feat-x
cleanup_fixture

# --- case: nothing to merge ---
mkfixture_local merge_nothing
cd "$FIXTURE_SUPER"
./subgrove new feat-y >out 2>&1
./subgrove merge feat-y >out 2>&1
assert_grep out "Nothing to merge"
cleanup_fixture

# --- case: partial — only one submodule has changes ---
mkfixture_local merge_partial
cd "$FIXTURE_SUPER"
./subgrove new feat-p >out 2>&1
commit_one .worktree/feat-p/sm-a "sm-a change"
( cd .worktree/feat-p && git add -A && git commit --quiet -m "bump sm-a" )

feat_a="$(git -C .worktree/feat-p/sm-a rev-parse feat/feat-p)"
main_b_before="$(git -C sm-b rev-parse main)"

./subgrove merge feat-p >out 2>&1
assert_branch_at sm-a main "$feat_a"
assert_branch_at sm-b main "$main_b_before"
assert_grep out "skip"
cleanup_fixture

# --- case: dirty parent (dst) — no submodule mains advance (two-phase) ---
mkfixture_local merge_dirty_dst_parent
cd "$FIXTURE_SUPER"
./subgrove new feat-x >out 2>&1
commit_one .worktree/feat-x/sm-a "sm-a change"
commit_one .worktree/feat-x/sm-b "sm-b change"
( cd .worktree/feat-x && git add -A && git commit --quiet -m "bump" )
echo "dirty" >> README
main_a_before="$(git -C sm-a rev-parse main)"
main_b_before="$(git -C sm-b rev-parse main)"
if ./subgrove merge feat-x >out 2>&1; then
    fail "expected merge to refuse on dirty parent (dst)"
fi
assert_branch_at sm-a main "$main_a_before"
assert_branch_at sm-b main "$main_b_before"
cleanup_fixture

# --- case: dirty submodule (dst) refused ---
mkfixture_local merge_dirty_dst_sm
cd "$FIXTURE_SUPER"
./subgrove new feat-x >out 2>&1
commit_one .worktree/feat-x/sm-a "sm-a change"
( cd .worktree/feat-x && git add -A && git commit --quiet -m "bump" )
echo "dirty" >> sm-a/README
main_a_before="$(git -C sm-a rev-parse main)"
if ./subgrove merge feat-x >out 2>&1; then
    fail "expected merge to refuse on dirty submodule (dst)"
fi
assert_branch_at sm-a main "$main_a_before"
cleanup_fixture

# --- case: non-FF parent ---
mkfixture_local merge_nonff_parent
cd "$FIXTURE_SUPER"
./subgrove new feat-x >out 2>&1
commit_one .worktree/feat-x "feat parent commit"
echo "main-side parent change" >> README
git add README
git commit --quiet -m "main-side parent"
main_super_before="$(git rev-parse main)"
if ./subgrove merge feat-x >out 2>&1; then
    fail "expected merge to refuse on non-FF parent"
fi
assert_branch_at . main "$main_super_before"
cleanup_fixture

# --- case: non-FF submodule (two-phase invariant) ---
# sm-b's main is divergent. The merge MUST refuse without having moved
# sm-a's main first. The divergence is staged via a detached-HEAD trick so
# the parent stays clean (otherwise the Phase 0 dirty check would fire
# before the Phase 1 FF check we're trying to exercise).
mkfixture_local merge_two_phase
cd "$FIXTURE_SUPER"
./subgrove new feat-x >out 2>&1
commit_one .worktree/feat-x/sm-a "sm-a feat change"
commit_one .worktree/feat-x/sm-b "sm-b feat change"
( cd .worktree/feat-x && git add -A && git commit --quiet -m "bump" )
(
    cd sm-b
    git checkout --quiet --detach
    new_sha="$(git commit-tree -m diverge -p main "$(git rev-parse main^{tree})")"
    git update-ref refs/heads/main "$new_sha"
)
main_a_before="$(git -C sm-a rev-parse main)"
main_b_before="$(git -C sm-b rev-parse main)"
if ./subgrove merge feat-x >out 2>&1; then
    fail "expected merge to refuse on non-FF sm-b"
fi
# THE invariant: sm-a's main UNCHANGED despite sm-b's failure.
assert_branch_at sm-a main "$main_a_before"
assert_branch_at sm-b main "$main_b_before"
cleanup_fixture

# --- case: peer propagation (clean peer) ---
mkfixture_local merge_peer_clean
cd "$FIXTURE_SUPER"
./subgrove new feat-x >out 2>&1
./subgrove new feat-y >out 2>&1
commit_one .worktree/feat-x/sm-a "sm-a change"
( cd .worktree/feat-x && git add -A && git commit --quiet -m "bump" )

./subgrove merge feat-x >out 2>&1

feat_a="$(git -C .worktree/feat-x/sm-a rev-parse feat/feat-x)"
assert_branch_at .worktree/feat-y/sm-a main "$feat_a"
cleanup_fixture

# --- case: peer with main checked out → propagation skipped ---
mkfixture_local merge_peer_main_co
cd "$FIXTURE_SUPER"
./subgrove new feat-x >out 2>&1
./subgrove new feat-y >out 2>&1
( cd .worktree/feat-y/sm-a && git checkout --quiet main )
peer_main_before="$(git -C .worktree/feat-y/sm-a rev-parse main)"

commit_one .worktree/feat-x/sm-a "sm-a change"
( cd .worktree/feat-x && git add -A && git commit --quiet -m "bump" )

./subgrove merge feat-x >out 2>&1
assert_grep out "main checked out"
peer_main_after="$(git -C .worktree/feat-y/sm-a rev-parse main)"
assert_eq "$peer_main_before" "$peer_main_after"
cleanup_fixture

# --- case: peer's main diverged → propagation skipped ---
mkfixture_local merge_peer_diverged
cd "$FIXTURE_SUPER"
./subgrove new feat-x >out 2>&1
./subgrove new feat-y >out 2>&1
(
    cd .worktree/feat-y/sm-a
    new_sha="$(git commit-tree -m diverge -p main "$(git rev-parse main^{tree})")"
    git update-ref refs/heads/main "$new_sha"
)

commit_one .worktree/feat-x/sm-a "sm-a change"
( cd .worktree/feat-x && git add -A && git commit --quiet -m "bump" )

./subgrove merge feat-x >out 2>&1
assert_grep out "diverged"
cleanup_fixture

# --- case: nonexistent branch refused ---
mkfixture_local merge_nonexistent
cd "$FIXTURE_SUPER"
if ./subgrove merge never-existed >out 2>&1; then
    fail "expected merge to fail on nonexistent name"
fi
cleanup_fixture

# --- case: dirty source parent (feature worktree) refused ---
mkfixture_local merge_dirty_src_parent
cd "$FIXTURE_SUPER"
./subgrove new feat-x >out 2>&1
commit_one .worktree/feat-x/sm-a "sm-a change"
( cd .worktree/feat-x && git add -A && git commit --quiet -m "bump" )
echo "dirty src" >> .worktree/feat-x/README
main_a_before="$(git -C sm-a rev-parse main)"
if ./subgrove merge feat-x >out 2>&1; then
    fail "expected merge to refuse on dirty src parent"
fi
assert_branch_at sm-a main "$main_a_before"
cleanup_fixture

# --- case: dirty source submodule (feature worktree) refused ---
mkfixture_local merge_dirty_src_sm
cd "$FIXTURE_SUPER"
./subgrove new feat-x >out 2>&1
commit_one .worktree/feat-x/sm-a "sm-a change"
( cd .worktree/feat-x && git add -A && git commit --quiet -m "bump" )
echo "dirty src" >> .worktree/feat-x/sm-a/README
main_a_before="$(git -C sm-a rev-parse main)"
if ./subgrove merge feat-x >out 2>&1; then
    fail "expected merge to refuse on dirty src submodule"
fi
assert_branch_at sm-a main "$main_a_before"
cleanup_fixture

# --- case: peer propagation reaches multiple peer worktrees ---
mkfixture_local merge_multi_peer
cd "$FIXTURE_SUPER"
./subgrove new feat-x >out 2>&1
./subgrove new feat-y >out 2>&1
./subgrove new feat-z >out 2>&1
commit_one .worktree/feat-x/sm-a "sm-a change"
( cd .worktree/feat-x && git add -A && git commit --quiet -m "bump" )

./subgrove merge feat-x >out 2>&1

feat_a="$(git -C .worktree/feat-x/sm-a rev-parse feat/feat-x)"
assert_branch_at .worktree/feat-y/sm-a main "$feat_a"
assert_branch_at .worktree/feat-z/sm-a main "$feat_a"
cleanup_fixture
