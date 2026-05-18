#!/usr/bin/env bash
# Tests for `subgrove new`.
set -eo pipefail

. "$(dirname "$0")/../lib/assert.sh"
. "$(dirname "$0")/../lib/fixture_local.sh"

# --- case: golden, touch=all default ---
mkfixture_local new_golden
cd "$FIXTURE_SUPER"
./subgrove new feat-x >out 2>&1
assert_file_exists .worktree/feat-x
assert_head_on .worktree/feat-x feat/feat-x
assert_head_on .worktree/feat-x/sm-a feat/feat-x
assert_head_on .worktree/feat-x/sm-b feat/feat-x
# Super has no origin; subgrove's base falls back to local main.
assert_branch_at . feat/feat-x "$(git rev-parse main)"
cleanup_fixture

# --- case: touch=sm-a (subset) ---
mkfixture_local new_touch_subset
cd "$FIXTURE_SUPER"
./subgrove new feat-y touch=sm-a >out 2>&1
assert_head_on .worktree/feat-y/sm-a feat/feat-y
assert_no_branch .worktree/feat-y/sm-b feat/feat-y
cleanup_fixture

# --- case: touch=none (parent only) ---
mkfixture_local new_touch_none
cd "$FIXTURE_SUPER"
./subgrove new feat-z touch=none >out 2>&1
assert_head_on .worktree/feat-z feat/feat-z
assert_no_branch .worktree/feat-z/sm-a feat/feat-z
assert_no_branch .worktree/feat-z/sm-b feat/feat-z
cleanup_fixture

# --- case: build=false skips BUILD_CHAIN ---
mkfixture_local new_build_false
cd "$FIXTURE_SUPER"
cat > .subgroverc <<'EOF'
BUILD_CHAIN=(sm-a)
BUILD_CMD="touch .built"
COPY_TO_NEW_WORKTREE=()
BRANCH_PREFIX="feat/"
EOF
git add .subgroverc
git commit --quiet -m "enable BUILD_CHAIN for test"
./subgrove new feat-build-skip build=false >out 2>&1
assert_file_absent .worktree/feat-build-skip/sm-a/.built
assert_grep out "Build chain skipped"
cleanup_fixture

# --- case: build runs by default with BUILD_CHAIN ---
mkfixture_local new_build_runs
cd "$FIXTURE_SUPER"
cat > .subgroverc <<'EOF'
BUILD_CHAIN=(sm-a)
BUILD_CMD="touch .built"
COPY_TO_NEW_WORKTREE=()
BRANCH_PREFIX="feat/"
EOF
git add .subgroverc
git commit --quiet -m "enable BUILD_CHAIN for test"
./subgrove new feat-build >out 2>&1
assert_file_exists .worktree/feat-build/sm-a/.built
cleanup_fixture

# --- case: pre-existing worktree dir refused ---
mkfixture_local new_existing_dir
cd "$FIXTURE_SUPER"
mkdir -p .worktree/feat-collide
if ./subgrove new feat-collide >out 2>&1; then
    fail "expected new to fail on pre-existing worktree dir"
fi
assert_grep out "already exists"
assert_no_branch . feat/feat-collide
cleanup_fixture

# --- case: pre-existing parent branch refused ---
mkfixture_local new_existing_branch
cd "$FIXTURE_SUPER"
git branch feat/feat-pre main
if ./subgrove new feat-pre >out 2>&1; then
    fail "expected new to fail on pre-existing branch"
fi
assert_grep out "already exists"
assert_file_absent .worktree/feat-pre
cleanup_fixture

# --- case: linked-worktree refusal ---
mkfixture_local new_linked
cd "$FIXTURE_SUPER"
./subgrove new feat-host >out 2>&1
ln -s "$SUBGROVE_REPO_ROOT/subgrove" .worktree/feat-host/subgrove
cd .worktree/feat-host
if ./subgrove new feat-from-linked >out 2>&1; then
    cd "$FIXTURE_SUPER"
    fail "expected new to refuse from a linked worktree"
fi
assert_grep out "main worktree"
cd "$FIXTURE_SUPER"
cleanup_fixture

# --- case: missing .worktree/ in .gitignore ---
mkfixture_local new_no_ignore
cd "$FIXTURE_SUPER"
> .gitignore
git add .gitignore
git commit --quiet -m "drop .worktree from .gitignore"
if ./subgrove new feat-noignore >out 2>&1; then
    fail "expected new to refuse when .worktree/ not gitignored"
fi
assert_grep out "not gitignored"
cleanup_fixture

# --- case: invalid name rejected ---
mkfixture_local new_invalid
cd "$FIXTURE_SUPER"
for bad in ".dotleading" "-dashleading" "spaces in name" "" "ba/d"; do
    if ./subgrove new "$bad" >out 2>&1; then
        fail "expected new to reject name '$bad'"
    fi
done
cleanup_fixture

# --- case: rollback on submodule-init failure ---
# Rename sibling sm-b so the file:// URL recorded in .gitmodules no longer
# resolves. `git submodule update --init` will fail in the new worktree.
# cmd_new's rollback trap should clean up the half-built worktree (rm +
# branch -D) so a retry of the same name wouldn't trip on residue.
mkfixture_local new_rollback
cd "$FIXTURE_SUPER"
mv "$FIXTURE_ROOT/sm-b" "$FIXTURE_ROOT/sm-b.disabled"
new_failed=0
./subgrove new feat-rollback >out 2>&1 || new_failed=1
mv "$FIXTURE_ROOT/sm-b.disabled" "$FIXTURE_ROOT/sm-b" 2>/dev/null || true
[[ $new_failed -eq 1 ]] || fail "expected new to fail on submodule init failure"
assert_file_absent .worktree/feat-rollback
assert_no_branch . feat/feat-rollback
cleanup_fixture

# --- case: COPY_TO_NEW_WORKTREE copies items from main super ---
mkfixture_local new_copy
cd "$FIXTURE_SUPER"
cat > .subgroverc <<'EOF'
BUILD_CHAIN=()
BUILD_CMD="true"
COPY_TO_NEW_WORKTREE=(.copy-me .copy-dir)
BRANCH_PREFIX="feat/"
EOF
git add .subgroverc
git commit --quiet -m "configure COPY_TO_NEW_WORKTREE"
echo "shared config" > .copy-me
mkdir -p .copy-dir && echo "in dir" > .copy-dir/file
./subgrove new feat-copy >out 2>&1
assert_file_exists .worktree/feat-copy/.copy-me
assert_file_exists .worktree/feat-copy/.copy-dir/file
cleanup_fixture

# --- case: COPY_TO_NEW_WORKTREE silently skips missing items ---
mkfixture_local new_copy_missing
cd "$FIXTURE_SUPER"
cat > .subgroverc <<'EOF'
BUILD_CHAIN=()
BUILD_CMD="true"
COPY_TO_NEW_WORKTREE=(.nonexistent-file)
BRANCH_PREFIX="feat/"
EOF
git add .subgroverc
git commit --quiet -m "configure COPY_TO_NEW_WORKTREE with missing item"
./subgrove new feat-skip >out 2>&1
assert_file_absent .worktree/feat-skip/.nonexistent-file
cleanup_fixture

# --- case: touch= with nonexistent submodule name refused ---
mkfixture_local new_touch_invalid
cd "$FIXTURE_SUPER"
if ./subgrove new feat-bad-touch touch=nonexistent >out 2>&1; then
    fail "expected new to fail on nonexistent submodule name in touch="
fi
assert_grep out "no such submodule path"
# Rollback fires, so the worktree dir is cleaned up.
assert_file_absent .worktree/feat-bad-touch
assert_no_branch . feat/feat-bad-touch
cleanup_fixture

# --- case: BUILD_CHAIN runs each module in order ---
mkfixture_local new_build_multi
cd "$FIXTURE_SUPER"
cat > .subgroverc <<'EOF'
BUILD_CHAIN=(sm-a sm-b)
BUILD_CMD="touch .built"
COPY_TO_NEW_WORKTREE=()
BRANCH_PREFIX="feat/"
EOF
git add .subgroverc
git commit --quiet -m "BUILD_CHAIN with two modules"
./subgrove new feat-multi >out 2>&1
assert_file_exists .worktree/feat-multi/sm-a/.built
assert_file_exists .worktree/feat-multi/sm-b/.built
cleanup_fixture

# --- case: dirty main super doesn't block new ---
# cmd_new doesn't `require_clean` the main super, so uncommitted changes
# in the surrounding super (parent and submodules) should not prevent
# creating a new worktree.
mkfixture_local new_dirty_super_ok
cd "$FIXTURE_SUPER"
echo "dirty parent" >> README
echo "dirty sm-a" >> sm-a/README
echo "dirty sm-b" >> sm-b/README
./subgrove new feat-x >out 2>&1
assert_file_exists .worktree/feat-x
assert_head_on .worktree/feat-x feat/feat-x
cleanup_fixture
