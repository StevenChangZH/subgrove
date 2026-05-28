#!/usr/bin/env bash
# Tests for the bash completion (completions/subgrove.bash).
#
# No mocks: source the real completion, drive its _subgrove function with
# synthetic COMP_WORDS/COMP_CWORD against a real fixture, and inspect the
# resulting COMPREPLY. The zsh completion is syntax-checked when zsh exists.
set -eo pipefail

. "$(dirname "$0")/../lib/assert.sh"
. "$(dirname "$0")/../lib/fixture_local.sh"

COMPLETION_BASH="$SUBGROVE_REPO_ROOT/completions/subgrove.bash"
COMPLETION_ZSH="$SUBGROVE_REPO_ROOT/completions/_subgrove"

# _complete CWORD WORD...  -> runs the completion, fills COMPREPLY
_complete() {
    COMP_CWORD="$1"; shift
    COMP_WORDS=("$@")
    COMPREPLY=()
    _subgrove
}
_reply_has() {
    local want="$1" r
    for r in "${COMPREPLY[@]}"; do [[ "$r" == "$want" ]] && return 0; done
    printf 'COMPREPLY: [%s]\n' "${COMPREPLY[*]}" >&2
    fail "completion missing candidate: $want"
}
_reply_lacks() {
    local nope="$1" r
    for r in "${COMPREPLY[@]}"; do
        if [[ "$r" == "$nope" ]]; then
            printf 'COMPREPLY: [%s]\n' "${COMPREPLY[*]}" >&2
            fail "completion unexpectedly offered: $nope"
        fi
    done
    return 0
}

# --- case: subcommands complete at position 1 ---
mkfixture_local comp_subcmds
cd "$FIXTURE_SUPER"
. "$COMPLETION_BASH"
_complete 1 subgrove ""
_reply_has new
_reply_has merge
_reply_has update
_reply_has remove
_reply_has status
_reply_has init
_reply_has list
# prefix filter
_complete 1 subgrove "re"
_reply_has remove
_reply_lacks new
cleanup_fixture

# --- case: existing worktree names complete for status/remove ---
mkfixture_local comp_worktrees
cd "$FIXTURE_SUPER"
./subgrove new feat-a >out 2>&1
./subgrove new feat-b >out 2>&1
. "$COMPLETION_BASH"
_complete 2 subgrove status ""
_reply_has feat-a
_reply_has feat-b
_complete 2 subgrove remove ""
_reply_has feat-a
_reply_has feat-b
# prefix filter narrows to the matching worktree
_complete 2 subgrove remove "feat-a"
_reply_has feat-a
_reply_lacks feat-b
cleanup_fixture

# --- case: touch= completes submodule paths from .gitmodules ---
mkfixture_local comp_touch
cd "$FIXTURE_SUPER"
. "$COMPLETION_BASH"
_complete 3 subgrove new x "touch="
_reply_has "touch=sm-a"
_reply_has "touch=sm-b"
cleanup_fixture

# --- case: key=value flags complete true/false ---
mkfixture_local comp_kv
cd "$FIXTURE_SUPER"
. "$COMPLETION_BASH"
_complete 3 subgrove new x "build="
_reply_has "build=true"
_reply_has "build=false"
_complete 3 subgrove merge x "push="
_reply_has "push=true"
_complete 3 subgrove remove x "force="
_reply_has "force=true"
cleanup_fixture

# --- case: zsh completion parses (only where zsh is installed) ---
mkfixture_local comp_zsh_syntax
cd "$FIXTURE_SUPER"
if command -v zsh >/dev/null 2>&1; then
    zsh -n "$COMPLETION_ZSH" || fail "zsh completion ($COMPLETION_ZSH) has a syntax error"
else
    echo "    (zsh not installed — skipping zsh syntax check)" >&2
fi
cleanup_fixture
