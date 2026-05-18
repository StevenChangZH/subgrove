#!/usr/bin/env bash
# State matrix for `subgrove merge`. Iterates every combination of
# (uncommitted, commits) across parent + sm-a + sm-b in the feature
# worktree — 2^6 = 64 combinations.
#
# Each iteration builds a fresh fixture, sets up the state, runs
# `subgrove merge feat-x`, and verifies the outcome.
#
# Staging dimension: `staged` alternates per iteration so both variants
# of `require_clean` (it checks both `git diff --quiet` AND
# `git diff --cached --quiet`) get exercised across the matrix.
#
# Implicit parent dirty: when a submodule has commits but `parent_commits`
# is 0, the parent's working tree shows `M <submodule>` (recorded SHA in
# parent's index doesn't match the new submodule HEAD). That counts as a
# dirty parent for require_clean's purposes. The prediction logic below
# folds this into `effective_parent_dirty`.
set -eo pipefail

. "$(dirname "$0")/../lib/assert.sh"
. "$(dirname "$0")/../lib/fixture_local.sh"

_apply_dirty() {
    local dir="$1" staged="$2"
    echo "dirty $$ $RANDOM" >> "$dir/README"
    if [[ "$staged" -eq 1 ]]; then
        git -C "$dir" add README
    fi
}

_run_case() {
    local p_unc="$1" p_com="$2" a_unc="$3" a_com="$4" b_unc="$5" b_com="$6" staged="$7"
    local label="P=(u=$p_unc,c=$p_com) A=(u=$a_unc,c=$a_com) B=(u=$b_unc,c=$b_com) staged=$staged"

    mkfixture_local "merge_matrix"
    cd "$FIXTURE_SUPER"

    ./subgrove new feat-x >/dev/null 2>&1 \
        || { echo "[$label]"; fail "new failed"; }

    # Commits: submodules first (they advance their own feat branches),
    # then parent (which captures the bumps + any parent-only edit).
    if [[ "$a_com" -eq 1 ]]; then commit_one .worktree/feat-x/sm-a "sm-a feat"; fi
    if [[ "$b_com" -eq 1 ]]; then commit_one .worktree/feat-x/sm-b "sm-b feat"; fi
    if [[ "$p_com" -eq 1 ]]; then
        (
            cd .worktree/feat-x
            # If no submodule commits, give the parent its own edit to
            # commit. Otherwise the commit captures the submodule bumps.
            if [[ "$a_com" -eq 0 && "$b_com" -eq 0 ]]; then
                echo "parent change" >> README
            fi
            git add -A
            git commit --quiet -m "parent commit"
        )
    fi

    # Dirty edits (AFTER commits, so the dirty isn't absorbed into a bump).
    if [[ "$p_unc" -eq 1 ]]; then _apply_dirty .worktree/feat-x        "$staged"; fi
    if [[ "$a_unc" -eq 1 ]]; then _apply_dirty .worktree/feat-x/sm-a   "$staged"; fi
    if [[ "$b_unc" -eq 1 ]]; then _apply_dirty .worktree/feat-x/sm-b   "$staged"; fi

    # Pre-merge state of main super's mains
    local pre_p pre_a pre_b
    pre_p="$(git rev-parse main)"
    pre_a="$(git -C sm-a rev-parse main)"
    pre_b="$(git -C sm-b rev-parse main)"

    local merge_failed=0
    ./subgrove merge feat-x >out 2>&1 || merge_failed=1

    # Predict
    local implicit_p_dirty=0
    if [[ ( "$a_com" -eq 1 || "$b_com" -eq 1 ) && "$p_com" -eq 0 ]]; then
        implicit_p_dirty=1
    fi
    local any_dirty=0
    if [[ "$p_unc" -eq 1 || "$a_unc" -eq 1 || "$b_unc" -eq 1 || "$implicit_p_dirty" -eq 1 ]]; then
        any_dirty=1
    fi
    local any_commits=0
    if [[ "$p_com" -eq 1 || "$a_com" -eq 1 || "$b_com" -eq 1 ]]; then
        any_commits=1
    fi

    if [[ "$any_dirty" -eq 1 ]]; then
        # Expect refuse + no mains moved.
        [[ "$merge_failed" -eq 1 ]] \
            || { echo "[$label]"; cat out; fail "expected merge to refuse on dirty"; }
        [[ "$(git rev-parse main)"        == "$pre_p" ]] \
            || { echo "[$label]"; fail "parent main advanced unexpectedly"; }
        [[ "$(git -C sm-a rev-parse main)" == "$pre_a" ]] \
            || { echo "[$label]"; fail "sm-a main advanced unexpectedly"; }
        [[ "$(git -C sm-b rev-parse main)" == "$pre_b" ]] \
            || { echo "[$label]"; fail "sm-b main advanced unexpectedly"; }
    elif [[ "$any_commits" -eq 0 ]]; then
        # All clean + no commits → "Nothing to merge".
        [[ "$merge_failed" -eq 0 ]] \
            || { echo "[$label]"; cat out; fail "expected merge to succeed (nothing to merge)"; }
        grep -qE "Nothing to merge" out \
            || { echo "[$label]"; fail "expected 'Nothing to merge' in output"; }
    else
        # Clean, has commits → merge succeeds; advance per commits.
        [[ "$merge_failed" -eq 0 ]] \
            || { echo "[$label]"; cat out; fail "expected merge to succeed"; }
        local parent_feat
        parent_feat="$(git -C .worktree/feat-x rev-parse feat/feat-x)"
        [[ "$(git rev-parse main)" == "$parent_feat" ]] \
            || { echo "[$label]"; fail "parent main should advance to feat tip"; }
        if [[ "$a_com" -eq 1 ]]; then
            local a_feat
            a_feat="$(git -C .worktree/feat-x/sm-a rev-parse feat/feat-x)"
            [[ "$(git -C sm-a rev-parse main)" == "$a_feat" ]] \
                || { echo "[$label]"; fail "sm-a main should advance"; }
        else
            [[ "$(git -C sm-a rev-parse main)" == "$pre_a" ]] \
                || { echo "[$label]"; fail "sm-a main should NOT advance"; }
        fi
        if [[ "$b_com" -eq 1 ]]; then
            local b_feat
            b_feat="$(git -C .worktree/feat-x/sm-b rev-parse feat/feat-x)"
            [[ "$(git -C sm-b rev-parse main)" == "$b_feat" ]] \
                || { echo "[$label]"; fail "sm-b main should advance"; }
        else
            [[ "$(git -C sm-b rev-parse main)" == "$pre_b" ]] \
                || { echo "[$label]"; fail "sm-b main should NOT advance"; }
        fi
    fi

    cleanup_fixture
}

# 64 combinations encoded as a 6-bit integer.
i=0
while [[ "$i" -lt 64 ]]; do
    p_unc=$(( (i >> 0) & 1 ))
    p_com=$(( (i >> 1) & 1 ))
    a_unc=$(( (i >> 2) & 1 ))
    a_com=$(( (i >> 3) & 1 ))
    b_unc=$(( (i >> 4) & 1 ))
    b_com=$(( (i >> 5) & 1 ))
    staged=$(( i & 1 ))   # alternate per iteration
    _run_case "$p_unc" "$p_com" "$a_unc" "$a_com" "$b_unc" "$b_com" "$staged"
    i=$(( i + 1 ))
done

echo "All 64 merge state combinations verified."
