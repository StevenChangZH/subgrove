#!/usr/bin/env bash
# Shared mutators used by tests to construct conflict / non-FF / dirty
# states from a clean fixture. Sourced by both fixture_local.sh and
# fixture_remote.sh.

# dirty DIR — adds an uncommitted change at DIR.
dirty() {
    local dir="$1"
    ( cd "$dir" && {
        if [[ -f README ]]; then
            echo "dirty $$" >> README
        else
            echo "dirty $$" > dirty.txt
            git add dirty.txt
        fi
    } )
}

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

# force_diverge REPO BRANCH — checks out BRANCH and commits to it, producing
# a history that cannot fast-forward from any upstream.
force_diverge() {
    local repo="$1" branch="$2"
    ( cd "$repo" && {
        git checkout --quiet "$branch"
        echo "diverge $$ $RANDOM" >> README
        git add -A
        git commit --quiet -m "diverge"
    } )
}

# checkout_main_in DIR — switches DIR's HEAD to refs/heads/main.
checkout_main_in() {
    local dir="$1"
    ( cd "$dir" && git checkout --quiet main )
}
