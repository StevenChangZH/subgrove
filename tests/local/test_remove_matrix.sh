#!/usr/bin/env bash
# State matrix for `subgrove remove`. Iterates every combination of
# (dirty, no-dirty) for the parent + sm-a + sm-b in the feature worktree
# (2^3 = 8 dirty combinations) × 2 staged variants × 2 force-flag values
# = 32 iterations.
#
# Outcome:
# - force=1: remove succeeds regardless of dirty state.
# - force=0 + any dirty: remove refused, worktree intact.
# - force=0 + all clean: remove succeeds.
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
    local p_d="$1" a_d="$2" b_d="$3" staged="$4" force="$5"
    local label="P_dirty=$p_d A_dirty=$a_d B_dirty=$b_d staged=$staged force=$force"

    mkfixture_local "remove_matrix"
    cd "$FIXTURE_SUPER"

    ./subgrove new feat-x >/dev/null 2>&1 \
        || { echo "[$label]"; fail "new failed"; }

    if [[ "$p_d" -eq 1 ]]; then _apply_dirty .worktree/feat-x      "$staged"; fi
    if [[ "$a_d" -eq 1 ]]; then _apply_dirty .worktree/feat-x/sm-a "$staged"; fi
    if [[ "$b_d" -eq 1 ]]; then _apply_dirty .worktree/feat-x/sm-b "$staged"; fi

    local args=()
    [[ "$force" -eq 1 ]] && args+=(-f)

    local remove_failed=0
    ./subgrove remove feat-x "${args[@]}" >out 2>&1 || remove_failed=1

    local any_dirty=0
    if [[ "$p_d" -eq 1 || "$a_d" -eq 1 || "$b_d" -eq 1 ]]; then
        any_dirty=1
    fi

    if [[ "$force" -eq 1 ]]; then
        # Force wins regardless of dirty.
        [[ "$remove_failed" -eq 0 ]] \
            || { echo "[$label]"; cat out; fail "expected remove -f to succeed"; }
        [[ ! -e .worktree/feat-x ]] \
            || { echo "[$label]"; fail "worktree should be gone"; }
    elif [[ "$any_dirty" -eq 1 ]]; then
        # Dirty without force → refuse, worktree intact.
        [[ "$remove_failed" -eq 1 ]] \
            || { echo "[$label]"; cat out; fail "expected remove to refuse on dirty"; }
        [[ -e .worktree/feat-x ]] \
            || { echo "[$label]"; fail "worktree should be intact"; }
    else
        # All clean, no force → succeed.
        [[ "$remove_failed" -eq 0 ]] \
            || { echo "[$label]"; cat out; fail "expected remove to succeed (clean)"; }
        [[ ! -e .worktree/feat-x ]] \
            || { echo "[$label]"; fail "worktree should be gone"; }
    fi

    cleanup_fixture
}

i=0
while [[ "$i" -lt 32 ]]; do
    p_d=$(( (i >> 0) & 1 ))
    a_d=$(( (i >> 1) & 1 ))
    b_d=$(( (i >> 2) & 1 ))
    staged=$(( (i >> 3) & 1 ))
    force=$(( (i >> 4) & 1 ))
    _run_case "$p_d" "$a_d" "$b_d" "$staged" "$force"
    i=$(( i + 1 ))
done

echo "All 32 remove state combinations verified."
