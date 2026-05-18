#!/usr/bin/env bash
# Assertions for subgrove tests. macOS bash 3.2 compatible.
#
# Each helper exits non-zero (via `fail`) on assertion failure. Tests run
# under `set -eo pipefail`, so a failed assertion aborts the test and the
# fixture is preserved for inspection.

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$expected" != "$actual" ]]; then
        fail "${msg:+$msg: }expected '$expected', got '$actual'"
    fi
}

assert_ne() {
    local a="$1" b="$2" msg="${3:-}"
    if [[ "$a" == "$b" ]]; then
        fail "${msg:+$msg: }expected '$a' != '$b' but they are equal"
    fi
}

# assert_branch_at GIT_DIR BRANCH [EXPECTED_REF_OR_SHA]
# Without EXPECTED: asserts BRANCH exists in GIT_DIR.
# With EXPECTED: asserts the branch's SHA equals EXPECTED's resolution.
assert_branch_at() {
    local git_dir="$1" branch="$2" expected="${3:-}"
    local actual_sha
    actual_sha="$(git -C "$git_dir" rev-parse --verify --quiet "refs/heads/$branch" 2>/dev/null)" \
        || fail "branch '$branch' missing in $git_dir"
    if [[ -n "$expected" ]]; then
        local expected_sha
        expected_sha="$(git -C "$git_dir" rev-parse --verify --quiet "$expected" 2>/dev/null \
                       || git rev-parse --verify --quiet "$expected" 2>/dev/null \
                       || echo "$expected")"
        if [[ "$actual_sha" != "$expected_sha" ]]; then
            fail "branch '$branch' in $git_dir at $actual_sha, expected $expected_sha (from '$expected')"
        fi
    fi
}

# assert_head_on DIR BRANCH — asserts HEAD is symbolic-ref to refs/heads/BRANCH.
assert_head_on() {
    local dir="$1" branch="$2"
    local actual
    actual="$(git -C "$dir" symbolic-ref --quiet HEAD 2>/dev/null || true)"
    if [[ "$actual" != "refs/heads/$branch" ]]; then
        fail "$dir: expected HEAD on refs/heads/$branch, got '${actual:-(detached)}'"
    fi
}

assert_no_branch() {
    local git_dir="$1" branch="$2"
    if git -C "$git_dir" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null 2>&1; then
        fail "branch '$branch' unexpectedly exists in $git_dir"
    fi
}

assert_clean() {
    local dir="$1"
    if ! git -C "$dir" diff --quiet 2>/dev/null; then
        fail "$dir has unstaged changes (expected clean)"
    fi
    if ! git -C "$dir" diff --cached --quiet 2>/dev/null; then
        fail "$dir has staged changes (expected clean)"
    fi
}

assert_dirty() {
    local dir="$1"
    if git -C "$dir" diff --quiet 2>/dev/null && git -C "$dir" diff --cached --quiet 2>/dev/null; then
        fail "$dir is clean (expected dirty)"
    fi
}

assert_grep() {
    local file="$1" pattern="$2"
    if ! grep -qE -- "$pattern" "$file"; then
        echo "--- contents of $file ---" >&2
        cat "$file" >&2
        echo "--- end ---" >&2
        fail "pattern '$pattern' not found in $file"
    fi
}

assert_grep_v() {
    local file="$1" pattern="$2"
    if grep -qE -- "$pattern" "$file"; then
        fail "pattern '$pattern' unexpectedly found in $file"
    fi
}

assert_file_exists() {
    local path="$1"
    [[ -e "$path" ]] || fail "expected to exist: $path"
}

assert_file_absent() {
    local path="$1"
    [[ ! -e "$path" ]] || fail "expected to NOT exist: $path"
}
