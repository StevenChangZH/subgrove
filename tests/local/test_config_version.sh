#!/usr/bin/env bash
# The .subgroverc version gate (SUBGROVE_CONFIG_VERSION).
#
# subgrove compares only the MAJOR component of the config's recorded version
# against its own VERSION. An "invalid" config — the field missing, or a
# different major — is fatal for mutating commands (new/merge/update/remove)
# but only a warning for read-only ones (status/list), so the diagnostic
# commands still work on an out-of-date config. `init` is exempt and repairs
# the field. See docs/design/config-version.md.
set -eo pipefail

. "$(dirname "$0")/../lib/assert.sh"
. "$(dirname "$0")/../lib/fixture_local.sh"

# The running script's version + its major, read the same way test_version.sh
# single-sources it. major-only matching means these tests stay valid across
# every 0.x release without edits.
sgver="$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$SUBGROVE_REPO_ROOT/subgrove")"
[[ -n "$sgver" ]] || fail "could not read VERSION= from subgrove"
major="${sgver%%.*}"

# write_config VERSIONVALUE — rewrite .subgroverc with the given
# SUBGROVE_CONFIG_VERSION (pass "" to omit the line entirely), keeping the rest
# of the config valid. Not committed: `new` reads the file off disk, and the
# version gate fires before any cleanliness check.
write_config() {
    {
        [[ -n "$1" ]] && printf 'SUBGROVE_CONFIG_VERSION="%s"\n' "$1"
        cat <<'EOF'
WORKTREES_DIR=".worktree"
BUILD_CHAIN=()
BUILD_CMD="true"
COPY_TO_NEW_WORKTREE=()
BRANCH_PREFIX="feat/"
EOF
    } > .subgroverc
}

# --- case: same major, wildly different minor/patch → accepted (major-only) ---
mkfixture_local cfgver_same_major
cd "$FIXTURE_SUPER"
write_config "${major}.99.99"
./subgrove new feat-x >out 2>&1 || { cat out; fail "new should accept a same-major config"; }
assert_grep_v out "SUBGROVE_CONFIG_VERSION"     # accepted silently — no version complaint
assert_head_on .worktree/feat-x feat/feat-x
# §15: status reflects the resulting state.
assert_status feat-x "feat/feat-x"
cleanup_fixture

# --- case: missing field → mutating commands refuse, no side effects ---
mkfixture_local cfgver_missing_mutating
cd "$FIXTURE_SUPER"
write_config ""                                 # omit SUBGROVE_CONFIG_VERSION entirely
for sub in "new feat-x" "merge feat-x" "remove feat-x" "update feat-x"; do
    if ./subgrove $sub >out 2>&1; then
        cat out; fail "expected '$sub' to refuse on a config missing SUBGROVE_CONFIG_VERSION"
    fi
    assert_grep out "no SUBGROVE_CONFIG_VERSION"
    assert_grep out "subgrove init"
done
# The refused 'new' created nothing (gate fires before any side effect).
assert_file_absent .worktree/feat-x
assert_no_branch . feat/feat-x
cleanup_fixture

# --- case: missing field → read-only commands warn but still run ---
mkfixture_local cfgver_missing_readonly
cd "$FIXTURE_SUPER"
write_config ""
# status warns on stderr, exits 0, and still renders the table.
./subgrove status >out 2>&1 || { cat out; fail "status should still run on an invalid-version config"; }
assert_grep out "warning"
assert_grep out "SUBGROVE_CONFIG_VERSION"
assert_grep out "WORKTREE"                       # the table still rendered
assert_grep_v out "ATTENTION"                    # warning is a plain line, not the tagged section
# list gets the same lenient treatment.
./subgrove list >out 2>&1 || { cat out; fail "list should still run on an invalid-version config"; }
assert_grep out "warning"
cleanup_fixture

# --- case: different major → mutating refuses, read-only warns ---
mkfixture_local cfgver_wrong_major
cd "$FIXTURE_SUPER"
write_config "$((major + 1)).0.0"                # next major up → incompatible
if ./subgrove new feat-x >out 2>&1; then
    cat out; fail "expected new to refuse on a different-major config"
fi
assert_grep out "incompatible"
assert_grep out "subgrove init"
assert_file_absent .worktree/feat-x
# read-only still runs (with a warning naming the mismatch).
./subgrove status >out 2>&1 || { cat out; fail "status should still run on a wrong-major config"; }
assert_grep out "warning"
assert_grep out "incompatible"
cleanup_fixture

# --- case: init repairs a config that is missing the version field ---
mkfixture_local cfgver_init_repairs
cd "$FIXTURE_SUPER"
write_config ""
git add .subgroverc && git commit --quiet -m "config without version"
# Mutating refuses first...
if ./subgrove new feat-x >out 2>&1; then cat out; fail "precondition: new should refuse"; fi
# ...init is exempt and stamps the running version...
./subgrove init --defaults >out 2>&1 || { cat out; fail "init should run on a versionless config"; }
assert_grep .subgroverc "SUBGROVE_CONFIG_VERSION=\"$sgver\""
# ...and now mutating works again.
./subgrove new feat-x >out 2>&1 || { cat out; fail "new should work after init repaired the version"; }
# §15: status reflects the resulting state.
assert_status feat-x "feat/feat-x"
cleanup_fixture

echo "PASS"
