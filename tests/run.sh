#!/usr/bin/env bash
# Entry point for subgrove tests. Plain bash, zero deps.
#
#   tests/run.sh                run all tests (local + remote)
#   tests/run.sh --local-only   skip the remote tests
#   tests/run.sh test_merge     substring filter against test basenames
#   tests/run.sh -v             stream each test's output live
#   tests/run.sh --clean        rm -rf tests/run/* and exit
#
# Remote-test URLs come from tests/config.sh (committed). Override per-run
# via env: SUBGROVE_TEST_SUPER_URL=... SUBGROVE_TEST_SM_URL=...
# SUBGROVE_TEST_SM_URL2=... tests/run.sh

set -eo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SUBGROVE_REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
# Fixtures live under tests/run/ (gitignored). Each fixture is a wholly
# separate git repo built by `git init` so tests can't operate on the
# current git. Override the base with SUBGROVE_TEST_FIXTURES_DIR.
SUBGROVE_TEST_FIXTURES_DIR="${SUBGROVE_TEST_FIXTURES_DIR:-$TESTS_DIR/run}"
export TESTS_DIR SUBGROVE_REPO_ROOT SUBGROVE_TEST_FIXTURES_DIR

mkdir -p "$SUBGROVE_TEST_FIXTURES_DIR"

# Load remote-test URLs from tests/config.sh unless they're already set in
# env. Env values take precedence (useful for ad-hoc runs against a fork
# without editing the committed file).
if [[ -z "${SUBGROVE_TEST_SUPER_URL:-}" \
   || -z "${SUBGROVE_TEST_SM_URL:-}" \
   || -z "${SUBGROVE_TEST_SM_URL2:-}" ]]; then
    if [[ -f "$TESTS_DIR/config.sh" ]]; then
        . "$TESTS_DIR/config.sh"
    fi
fi
export SUBGROVE_TEST_SUPER_URL SUBGROVE_TEST_SM_URL SUBGROVE_TEST_SM_URL2

usage() {
    cat <<'EOF'
Usage: tests/run.sh [-v] [--local-only] [--clean] [FILTER]

  -v             stream each test's output live (verbose)
  --local-only   skip tests/remote/ — run only the local tests
  --clean        rm -rf tests/fixtures/* and exit
  FILTER         run only tests whose basename contains FILTER

By default, runs all tests (local + remote). Remote-test URLs come from
tests/config.sh. Override with env:
  SUBGROVE_TEST_SUPER_URL=<git url for test superproject>
  SUBGROVE_TEST_SM_URL=<git url for first test submodule (sm-a)>
  SUBGROVE_TEST_SM_URL2=<git url for second test submodule (sm-b)>
EOF
}

verbose=0
local_only=0
filter=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) verbose=1; shift ;;
        --local-only) local_only=1; shift ;;
        --clean)
            echo "Cleaning $SUBGROVE_TEST_FIXTURES_DIR/"
            rm -rf "$SUBGROVE_TEST_FIXTURES_DIR"
            exit 0
            ;;
        -h|--help) usage; exit 0 ;;
        *) filter="$1"; shift ;;
    esac
done

tests=()
for t in "$TESTS_DIR"/local/test_*.sh; do
    [[ -f "$t" ]] || continue
    if [[ -n "$filter" ]]; then
        case "$(basename "$t")" in *"$filter"*) ;; *) continue ;; esac
    fi
    tests+=("$t")
done
if [[ $local_only -ne 1 ]]; then
    # Sanity-check remote-test config up front so we fail fast (and once)
    # rather than per-test.
    if [[ -z "${SUBGROVE_TEST_SUPER_URL:-}" \
       || -z "${SUBGROVE_TEST_SM_URL:-}" \
       || -z "${SUBGROVE_TEST_SM_URL2:-}" ]]; then
        echo "Remote tests: URLs not configured." >&2
        echo "  Edit $TESTS_DIR/config.sh to point at your fixture repos" >&2
        echo "  (SUBGROVE_TEST_SUPER_URL, SUBGROVE_TEST_SM_URL, SUBGROVE_TEST_SM_URL2)," >&2
        echo "  or pass --local-only to skip the remote tests." >&2
        exit 1
    fi
    for t in "$TESTS_DIR"/remote/test_*.sh; do
        [[ -f "$t" ]] || continue
        if [[ -n "$filter" ]]; then
            case "$(basename "$t")" in *"$filter"*) ;; *) continue ;; esac
        fi
        tests+=("$t")
    done
fi

if [[ ${#tests[@]} -eq 0 ]]; then
    if [[ -n "$filter" ]]; then
        echo "No tests matched filter '$filter'" >&2
    else
        echo "No tests found under $TESTS_DIR" >&2
    fi
    exit 1
fi

echo "Running ${#tests[@]} test(s)"
if [[ $local_only -eq 1 ]]; then
    echo "(remote tests skipped: --local-only)"
fi
echo

passed=0
failed=0
failed_names=()

for t in "${tests[@]}"; do
    name="$(basename "$t" .sh)"
    if [[ $verbose -eq 1 ]]; then
        echo "--- $name"
        if ( bash "$t" ); then
            passed=$((passed + 1))
            echo "+++ $name PASS"
        else
            failed=$((failed + 1))
            failed_names+=("$name")
            echo "+++ $name FAIL"
        fi
        echo
    else
        out="$(mktemp "${TMPDIR:-/tmp}/subgrove-test.XXXXXX")"
        if ( bash "$t" >"$out" 2>&1 ); then
            passed=$((passed + 1))
            echo "  ok    $name"
        else
            failed=$((failed + 1))
            failed_names+=("$name")
            echo "  FAIL  $name"
            echo "    --- last 30 lines of $name output ---"
            tail -n 30 "$out" | sed 's/^/    /'
            echo "    --- end ---"
        fi
        rm -f "$out"
    fi
done

echo
echo "Passed: $passed"
echo "Failed: $failed"
if [[ $failed -gt 0 ]]; then
    echo "Failed tests:"
    for n in "${failed_names[@]}"; do echo "  - $n"; done
    exit 1
fi
