#!/usr/bin/env bash
# Shared mutator used by tests to construct conflict / non-FF / dirty
# states from a clean fixture. Sourced by both fixture_local.sh and
# fixture_remote.sh.
#
# Note: tests that need staging/divergence/checkout mutations do them
# inline (e.g. `git checkout --detach` + `update-ref` for divergence,
# `echo >> README` + optional `git add` for staged/unstaged dirty edits).
# Only `commit_one` is general enough to factor out here.

# commit_one REPO MSG — single-file edit + commit in REPO.
commit_one() {
    local repo="$1" msg="${2:-test commit}"
    ( cd "$repo" && {
        if [[ -f README ]]; then
            echo "commit $$ $RANDOM" >> README
        else
            echo "init $$ $RANDOM" > content.txt
        fi
        git add -A
        git commit --quiet -m "$msg"
    } )
}
