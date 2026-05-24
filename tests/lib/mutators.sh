#!/usr/bin/env bash
# Shared mutator used by tests to construct conflict / non-FF / dirty
# states from a clean fixture. Sourced by both fixture_local.sh and
# fixture_remote.sh.
#
# Note: tests that need staging/divergence/checkout mutations do them
# inline (e.g. `git checkout --detach` + `update-ref` for divergence,
# `echo >> README` + optional `git add` for staged/unstaged dirty edits).
# Only `commit_one` is general enough to factor out here.

# _mut_fail MSG — exit the script with FATAL message. Self-contained
# (does NOT depend on assert.sh being sourced) so the push helpers below
# can fail loud regardless of source order. The teardown trap (if armed
# by the caller) fires on this exit and releases any held remote lock.
_mut_fail() {
    echo "FATAL: $*" >&2
    exit 1
}

# _redact_url URL — echo URL with any embedded credentials masked.
# Used everywhere a URL is printed for human consumption (stderr banners,
# recovery-hint commands). Keeps the unredacted URL only for the actual
# git invocation. Protects against HTTPS-with-PAT URL env overrides
# (e.g. SUBGROVE_TEST_SUPER_URL=https://user:ghp_xxx@github.com/...)
# leaking into CI logs via the test output capture in tests/run.sh.
#
# The regex strips the `userinfo@` portion of a URL per RFC 3986. The
# match is GREEDY (`.*@` not `[^@]*@`) so a password containing a literal
# `@` is still fully masked — git accepts such passwords, and a non-greedy
# match would stop at the first `@` and leak the rest. The cost is
# over-redacting a credential-free URL that happens to contain `@` in its
# path (rare; strictly safer than under-redacting a real secret). Falls
# back to the unmodified URL for non-URL inputs (SSH `git@host:path`
# format and plain shell strings, which have no `://`).
_redact_url() {
    local url="$1"
    case "$url" in
        *://*@*)
            # scheme://userinfo@rest  →  scheme://REDACTED@rest
            printf '%s\n' "$url" | sed -E 's|://.*@|://REDACTED@|'
            ;;
        *)
            printf '%s\n' "$url"
            ;;
    esac
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

# push_to_origin_main URL [MSG]
# Simulates a third party pushing one commit to URL's main from a side
# clone. Echoes the new commit SHA on stdout (so tests can compare
# against it). Used by remote tests to drive "origin advanced under us"
# scenarios.
#
# Failure modes are LOUD via _mut_fail (exit 1) because bash 3.2 lacks
# inherit_errexit — a failed `sha=$(push_to_origin_main ...)` would
# otherwise propagate empty into downstream assertions and yield
# confusing "expected '', got '<sha>'" mismatches.
#
# The mktemp dir is rm'd whether the git operations succeed or fail —
# the `|| rc=$?` pattern keeps the cleanup unconditional under set -e.
push_to_origin_main() {
    local url="$1" msg="${2:-upstream commit}"
    local tmp sha rc=0
    tmp="$(mktemp -d -t subgrove-pushside.XXXXXX)"
    # `--` terminates git's option parsing so a URL accidentally starting
    # with `-` (or a poisoned config.sh string like `--upload-pack=...`)
    # is treated as a URL, not a CLI option.
    (
        git clone --quiet -- "$url" "$tmp/c"
        cd "$tmp/c"
        echo "$msg $$ $RANDOM" >> README
        git add README
        git commit --quiet -m "$msg"
        git push --quiet origin main
    ) >&2 || rc=$?
    if [[ $rc -eq 0 ]]; then
        sha="$(git -C "$tmp/c" rev-parse main)"
    fi
    rm -rf "$tmp"
    [[ $rc -eq 0 ]] || _mut_fail "push_to_origin_main: clone+push failed (rc=$rc)"
    [[ -n "$sha" ]]   || _mut_fail "push_to_origin_main: empty SHA after successful push"
    echo "$sha"
}

# push_n_to_origin_main URL N [MSG_PREFIX]
# N commits in a row on URL's main, from a side clone. Useful for
# "non-FF by many commits" scenarios where the test wants to be sure
# the rejection isn't a transient single-commit race. Same cleanup-
# always + fail-loud pattern as push_to_origin_main.
push_n_to_origin_main() {
    local url="$1" n="$2" prefix="${3:-upstream}"
    local tmp sha rc=0
    tmp="$(mktemp -d -t subgrove-pushside.XXXXXX)"
    (
        git clone --quiet -- "$url" "$tmp/c"
        cd "$tmp/c"
        local i
        for (( i=1; i<=n; i++ )); do
            echo "$prefix $i $$ $RANDOM" >> README
            git add README
            git commit --quiet -m "$prefix commit $i"
        done
        git push --quiet origin main
    ) >&2 || rc=$?
    if [[ $rc -eq 0 ]]; then
        sha="$(git -C "$tmp/c" rev-parse main)"
    fi
    rm -rf "$tmp"
    [[ $rc -eq 0 ]] || _mut_fail "push_n_to_origin_main: clone+push failed (rc=$rc)"
    [[ -n "$sha" ]]   || _mut_fail "push_n_to_origin_main: empty SHA after successful push"
    echo "$sha"
}
