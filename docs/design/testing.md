# Testing

Subgrove ships with a real-git test suite under `tests/`. Subgrove's logic is too tangled in git's actual behavior — submodule git-dir isolation, `upload-pack` advertising only `refs/heads/*`, `git fetch`'s refusal to update a checked-out branch — to mock cleanly. Every scenario builds real repos from scratch using plain `git init`, runs subgrove against the fixture, and asserts both the script's output and the resulting repository state.

## Layout

```
tests/
├── run.sh           # entry point; runs all tests or a filtered subset
├── config.sh        # remote-test URLs (committed; maintainer fills in)
├── lib/
│   ├── assert.sh    # assert_eq, assert_branch_at, assert_grep, ...
│   ├── mutators.sh  # dirty / commit_one / force_diverge / checkout_main_in
│   ├── fixture_local.sh
│   └── fixture_remote.sh
├── local/           # local-only tests (no GitHub)
├── remote/          # tests that push to real GitHub
└── run/             # gitignored; per-test fixtures land here at runtime
```

## Local tests (default)

The local fixture is three `git init`'d repos at `tests/run/<timestamp>-<name>/`:

- `sm-a/` — standalone submodule source, one commit on `main`
- `sm-b/` — same
- `super/` — `git init`'d in place (so it has **no** `origin`). The two submodules are wired in via `git submodule add file:///…/sm-a` and the equivalent for sm-b.

That super-has-no-origin shape matches the "user didn't configure a remote on the superproject" scenario the local tests are meant to cover. The submodules under `super/` get `file://` origins to their sibling repos (set automatically by `submodule add`) so subgrove can `git fetch` from them.

Tests cd into `super/` and invoke subgrove through a symlink to the script under test. "Upstream change" scenarios are simulated by committing directly in the sibling `sm-a/` or `sm-b/` repo — subgrove's `git fetch origin main` in the main super's submodule picks it up via `file://`.

Paths NOT covered locally:

- `merge push=true` — super has no `origin`, nothing to push to.
- `new`'s fresh-base-from-origin — same reason.

Both are covered by the remote tests.

## Remote tests (opt-in, default-on when configured)

Gated on three GitHub URLs in `tests/config.sh`:

- `SUBGROVE_TEST_SUPER_URL` — the test superproject
- `SUBGROVE_TEST_SM_URL` — first test submodule (mapped to `sm-a`)
- `SUBGROVE_TEST_SM_URL2` — second test submodule (mapped to `sm-b`)

Per-run flow:

1. **Lock.** `git ls-remote $SUBGROVE_TEST_SUPER_URL refs/tags/subgrove-test-lock`. If the tag exists, abort with the remediation command. Otherwise push the tag and register an `EXIT`/`INT`/`TERM` trap to delete it.
2. **Baseline reset.** Force-push an orphan baseline to each submodule repo's `main`. Build a super baseline whose `.gitmodules` references both URLs; force-push it to the super repo's `main`.
3. **Working clone.** Re-clone super into `tests/run/<ts>-remote-<name>/super/`, init both submodules, drop in `.gitignore` / `.subgroverc` / `subgrove` symlink.
4. **Teardown trap.** Delete every feature branch the run created on all three repos; delete the lock tag.

The remote tests are **intentionally serial**. The lock turns a parallel run from another machine into a fast failure rather than corrupted state. Run `tests/run.sh --local-only` to skip the remote tests entirely (useful in CI or for contributors without push access to the fixture repos).

Multi-submodule scenarios over the wire — `push=true` advancing both origins, partial `update` where only one submodule moved — are covered here. The two-phase merge half-state invariant stays local-only: forging a divergent submodule commit while keeping the parent clean is awkward over the wire without an extra contributor clone.

## Conventions

Each test file is one `bash` script under `set -eo pipefail`. Scenarios are comment-headed blocks (`# --- case: ... ---`); each builds its own fixture and ends with `cleanup_fixture` as the LAST line. Failures under `set -e` exit before `cleanup_fixture` runs, leaving the fixture on disk for inspection — the runner prints the path on failure.

The per-test subshell + per-scenario fixture is the only isolation. No setup/teardown helpers spanning blocks; reading the file top-to-bottom enumerates every scenario in order.

## Per-tier case lists

Every scenario, its setup, what it asserts, and which design invariant it guards:

- [testing-local.md](testing-local.md) — 58 single-case scenarios + 96 parametric matrix iterations across `test_new`, `test_remove`, `test_merge`, `test_update`, `test_list`/dispatcher, plus `test_merge_matrix` and `test_remove_matrix`.
- testing-remote.md — coming next.

The longer-form design notes from the original brainstorming pass are at [docs/superpowers/specs/2026-05-15-testing-design.md](../superpowers/specs/2026-05-15-testing-design.md).
