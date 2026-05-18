# Local tests

Tests under `tests/local/`. Run with `./tests/run.sh --local-only`. Each scenario builds a fresh fixture (`super/` + `sm-a/` + `sm-b/`, all via `git init`) under `tests/run/<timestamp>-<name>/` and invokes subgrove through a symlink to the script under test.

The local fixture has **no `origin`** on the superproject (it was `git init`'d in place, never cloned), matching the "user hasn't configured a remote" scenario. The submodules under `super/` do have `file://` origins to their sibling source repos (set automatically by `git submodule add`) — subgrove's submodule-level fetch paths can exercise against those.

154 scenarios across seven files (58 single-case scenarios + 96 parametric matrix iterations).

## `test_new.sh` (15)

| Scenario | Setup | Asserts | Guards |
|---|---|---|---|
| Golden (`touch=all` default) | clean fixture | `.worktree/feat-x/` exists; parent + both submodules on `feat/feat-x`; parent base SHA == local `main` | The happy-path branching contract. |
| `touch=sm-a` subset | `new feat-y touch=sm-a` | sm-a on `feat/feat-y`; sm-b has no such branch | The `touch=<list>` parser keeps the selection narrow. |
| `touch=none` | `new feat-z touch=none` | parent on `feat/feat-z`; neither submodule has the branch | The all/none/list trichotomy works at the empty extreme. |
| `build=false` skips BUILD_CHAIN | `BUILD_CHAIN=(sm-a)`, `BUILD_CMD="touch .built"`, then `new ... build=false` | `.built` absent in worktree's sm-a; "Build chain skipped" in output | The skip-build escape hatch. |
| Build runs by default | same BUILD_CHAIN, no `build=false` | `.built` exists in worktree's sm-a | The default-enabled build chain actually invokes BUILD_CMD in the right cwd. |
| Pre-existing worktree dir | `mkdir .worktree/feat-collide` before `new` | err with "already exists"; no parent branch | A duplicate `new` doesn't trample existing state. |
| Pre-existing parent branch | `git branch feat/feat-pre main` before `new` | err with "already exists"; no worktree dir | Same check, ref side. |
| Linked-worktree refusal | symlink subgrove inside `.worktree/feat-host/`, invoke from there | err mentioning "main worktree" | `assert_main_worktree` fires when invoked through a path that resolves inside a linked worktree. |
| Missing `.worktree/` in `.gitignore` | empty `.gitignore` in fixture super | err mentioning "not gitignored" | `assert_worktrees_ignored` actually fires; the error message points at the remediation. |
| Invalid names | `.dotleading`, `-dashleading`, `spaces in name`, empty, `ba/d` | err on each | `validate_name` covers the leading-char and char-class constraints. |
| Rollback on submodule-init failure | rename sibling `sm-b/` so its `file://` URL no longer resolves, then `new` | worktree dir gone; parent branch gone | The `EXIT`/`INT`/`TERM` trap from `lifecycle.md` actually cleans up a half-built worktree so a retry of the same name doesn't trip on residue. |
| `COPY_TO_NEW_WORKTREE` happy path | configure `COPY_TO_NEW_WORKTREE=(.copy-me .copy-dir)`; create those items in main super; then `new` | both items present in the new worktree | The copy-into-new-worktree step in `cmd_new` runs for files and dirs. |
| `COPY_TO_NEW_WORKTREE` missing item | configure `COPY_TO_NEW_WORKTREE=(.nonexistent-file)`; then `new` | new succeeds; the missing item is absent in the worktree | The `[[ -e ... ]]` guard silently skips items that don't exist in main super (per the commented contract). |
| `touch=` with nonexistent submodule | `new feat-bad-touch touch=nonexistent` | err mentioning "no such submodule path"; worktree dir gone; parent branch gone | The `[[ -d "$sm_path" ]] || err` guard fires and the rollback trap still cleans up the half-built worktree. |
| BUILD_CHAIN with multiple modules | `BUILD_CHAIN=(sm-a sm-b)`, `BUILD_CMD="touch .built"`; then `new` | `.built` exists in both worktree submodules | The BUILD_CHAIN loop runs each module's BUILD_CMD; order matters but every entry runs. |
| Dirty main super doesn't block | dirty parent + both submodules in main super before `new` | new succeeds; the new worktree's HEAD is on `feat/feat-x` | cmd_new doesn't `require_clean` — main super state is irrelevant. |

## `test_remove.sh` (10)

| Scenario | Setup | Asserts | Guards |
|---|---|---|---|
| Golden | `new feat-x` then `remove feat-x` | worktree gone; parent branch retained | Happy path. |
| Dirty parent worktree | edit a tracked file in `.worktree/feat-x/` | err; worktree intact | `require_clean` catches dirty parent. |
| Dirty touched submodule | edit in `.worktree/feat-x/sm-a/` | err; worktree intact | `require_clean` covers touched submodules. |
| Dirty UN-touched submodule | `new feat-x touch=sm-a` (sm-b not branched but still initialised), edit in `.worktree/feat-x/sm-b/` | err; worktree intact | The "every initialised submodule" rule from `lifecycle.md` — un-branched-but-edited submodules must not be silently wiped by `rm -rf`. |
| `-f` overrides dirty | dirty parent + `-f` | worktree gone | The force escape hatch. |
| `--force` alias | dirty parent + `--force` | worktree gone | Long-flag alias for `-f`. |
| `force=true` alias | dirty parent + `force=true` | worktree gone | Key=value alias. |
| Nonexistent name | `remove never-existed` | err | Doesn't silently no-op when the worktree isn't there. |
| Remove one of many | `new feat-a` + `new feat-b`; remove only `feat-a` | feat-a's worktree gone; feat-b's worktree intact; both branches retained | `git worktree prune` and `rm -rf` on one worktree don't disturb siblings. |
| Re-create same name after remove | `new feat-x` → `remove feat-x` → `new feat-x` | second `new` errs with "already exists"; after `git branch -D feat/feat-x`, the third `new` succeeds | Locks in the documented "branches retained after remove" behavior (lifecycle.md). |

## `test_merge.sh` (14)

| Scenario | Setup | Asserts | Guards |
|---|---|---|---|
| Golden | commits in parent + each submodule on `feat-x` | parent + each touched sm `main` FF'd in main worktree; worktree retained | Happy-path merge across all touched modules. |
| Nothing to merge | `new feat-y` (no commits) then `merge feat-y` | "Nothing to merge" in output; no refs moved | Phase-0 filter short-circuits when feat tip == main tip in every module. |
| Partial — one submodule unchanged | commit only in sm-a | sm-a in `needs_merge`; sm-b in `skipped`; sm-b main unchanged | The filter splits modules correctly when only some have feat commits. |
| Dirty parent (dst) refused | edit in main worktree's parent before merge | err in validation; **no submodule mains advanced** | The two-phase split means a dirty-parent failure doesn't leave half-moved submodules behind. |
| Dirty submodule (dst) refused | edit in main worktree's sm-a | err; no state change | Same on the submodule side. |
| Non-FF parent refused | direct commit on main worktree's parent main, then merge feat-x | err; main unchanged | The parent FF check fires before any submodule mutation. |
| **Non-FF submodule (two-phase invariant)** | feat-x has commits on sm-a AND sm-b; diverge sm-b's main in main worktree via detached-HEAD + `update-ref` (so parent stays clean and Phase 0 doesn't fire) | err in Phase 1; **sm-a main UNCHANGED in main worktree** | THE invariant from `merge.md` — a non-FF on submodule N+1 must NOT leave submodules 1..N already moved. This is the test that distinguishes the current two-phase implementation from the older one-pass version. |
| Peer propagation (clean peer) | `new feat-x` + `new feat-y`; commit on feat-x's sm-a; merge feat-x | feat-y's sm-a main matches the new sm-a main | Step 8 of `merge.md` — peer worktrees see the new submodule main after merge. |
| Peer with main checked out | feat-y/sm-a checked out on `main` (not on a feat branch) | propagation skipped; warn "main checked out"; peer main unchanged | The peer-propagation refusal when git would otherwise update a checked-out branch. |
| Peer's main diverged | forge a divergent commit on feat-y/sm-a's main via `commit-tree` + `update-ref` | propagation skipped; warn "diverged" | The non-`+` refspec refuses non-FF; the script's HEAD-inspection distinguishes "diverged" from "main checked out" — this test pins the diverged branch of that distinction. |
| Nonexistent branch | `merge never-existed` | err | Doesn't try to merge a non-existent ref. |
| Dirty source parent refused | edit a tracked file in `.worktree/feat-x/` (the feature worktree's parent) | err; main worktree's submodule mains unchanged | The dirty-check covers the SRC side too, not just DST (parent worktree being merged FROM must also be clean). |
| Dirty source submodule refused | edit a tracked file in `.worktree/feat-x/sm-a/` | err; main worktree's sm-a main unchanged | The dirty-check covers the SRC submodule on every touched submodule. |
| Multi-peer propagation | `new feat-x` + `new feat-y` + `new feat-z`; commit on feat-x/sm-a; merge feat-x | sm-a's main in BOTH feat-y AND feat-z matches the new sm-a main | The peer-propagation loop iterates every peer worktree, not just the first one. |

## `test_update.sh` (9)

| Scenario | Setup | Asserts | Guards |
|---|---|---|---|
| Happy path | `commit_one` directly in sibling `sm-a/` (no push needed); `update feat-y` | feat-y/sm-a main == new sm-a SHA | The full `_update_sync` sentinel flow from `update.md` — fetch into main super's submodule, stage `origin/main` under a transient head ref, fetch sentinel into peer's main, delete sentinel. |
| Sentinel cleanup on success | run update on a clean fixture | `refs/heads/_update_sync` absent in both main super submodules afterward | No leftover sentinel ref after a successful run. |
| Sentinel cleanup pre-existing | manually `update-ref refs/heads/_update_sync` before running update | update succeeds; ref absent after | The defensive pre-clean handles a sentinel left over from a prior interrupted run. |
| Peer with main checked out | feat-y/sm-a on `main`, sibling sm-a has a new commit | skipped with warn "main checked out"; peer main unchanged | The skip-on-checked-out-main path; matches `merge`'s analogous case. |
| Peer's main diverged | forge divergent commit on feat-y/sm-a's main + sibling sm-a has new commit | skipped with warn "diverged" | The non-FF refusal in `cmd_update`. |
| No `refs/remotes/origin/main` → skipped | `git remote remove origin` on main super's submodules, then update | warn "no refs/remotes/origin/main" | The "submodule has no origin/main to read from" skip path. |
| Doesn't require clean state | edit in `.worktree/feat-y/sm-a/`, then update | succeeds (ref-only) | The invariant from `implementation-notes.md` — `cmd_update` is ref-only and must not require clean working trees. |
| Nonexistent name | `update never-existed` | err | Doesn't silently no-op. |
| Multiple submodules update in one run | commit in BOTH sibling sm-a and sm-b; then update feat-y | both feat-y submodule mains advance to their respective new SHAs | The per-submodule loop in `cmd_update` handles every submodule independently; one update call can move multiple peer submodules. |
| Dirty main super doesn't block | dirty parent + both submodules in main super; commit in sibling sm-a; then update feat-y | update succeeds; feat-y's sm-a main advances to the new SHA | cmd_update is ref-only and doesn't `require_clean` — main super dirty state is irrelevant. |

## `test_list.sh` and dispatcher (8)

| Scenario | Asserts | Guards |
|---|---|---|
| `list` after `new feat-a feat-b` | output contains both worktree paths | `cmd_list` reports every worktree. |
| `ls` alias | same effect as `list` | The short alias works. |
| `subgrove` with no args | prints usage; exit 0 | Default subcommand is `help`, exit code is success. |
| `subgrove help` | prints usage; exit 0 | Explicit `help` matches the default-no-args behavior. |
| `subgrove bogus-cmd` | exit non-zero | Unknown subcommands fall through to the catch-all and exit 1. |
| `rm` alias | same effect as `remove` | Short alias for `remove`. |
| `subgrove -h` | prints usage; exit 0 | Short `-h` flag dispatches to `usage`. |
| `subgrove --help` | prints usage; exit 0 | Long `--help` flag dispatches to `usage`. |

## `test_merge_matrix.sh` (64 iterations)

A single parametric test file that iterates **every** combination of `(uncommitted, commits)` across parent + sm-a + sm-b in the feature worktree — `2^6 = 64` cases. Each iteration:

1. Builds a fresh fixture.
2. Sets up the state (commits via `commit_one`; dirty edits via append to README; staging variant alternates per iteration so both `git diff --quiet` and `git diff --cached --quiet` paths of `require_clean` get exercised across the matrix).
3. Runs `subgrove merge feat-x`.
4. Verifies the outcome:
   - **Any effective dirty** (explicit uncommitted edit, OR implicit `M <submodule>` from a submodule that committed without parent bumping) → merge refused, **no** mains advanced.
   - **All clean + no commits anywhere** → "Nothing to merge"; refs unchanged.
   - **All clean + some commits** → merge succeeds; parent main advances to feat tip; each submodule main advances iff that submodule had commits.

The prediction logic that folds "implicit parent dirty from unbumped submodule commits" into the dirty path lives in the test itself — see the `implicit_p_dirty` computation. This is what makes the matrix's 64 cases tractable instead of contradictory: every combination is now coherent against a known expected outcome.

Guards: the entire dirty-refusal contract of `cmd_merge` across every state combination; the Phase-0 filter ("Nothing to merge", needs_merge vs skipped); the Phase-2 advancement contract; and the two-phase invariant ("non-FF on one module doesn't move other modules' mains") as a consequence of the no-mains-advanced assertion in the refuse branch.

## `test_remove_matrix.sh` (32 iterations)

Parametric matrix for `subgrove remove`: `2^3` dirty combinations × 2 staged variants × 2 force-flag values = 32 iterations. Each iteration:

1. Builds a fresh fixture; `subgrove new feat-x`.
2. Dirties locations as configured (staged or unstaged).
3. Runs `subgrove remove feat-x` (with `-f` when force=1).
4. Verifies:
   - `force=1` → succeeds regardless of dirty state; worktree gone.
   - `force=0` + any dirty → refused; worktree intact.
   - `force=0` + all clean → succeeds; worktree gone.

Guards: the `require_clean` × force-flag matrix across every per-location dirty combination, for both staged and unstaged variants.

## Tests intentionally NOT in `tests/local/`

These paths can't be exercised against the local fixture (super has no `origin`); they live in [testing-remote.md](testing-remote.md):

- `merge push=true` — super has no `origin` to push to.
- `new`'s fresh-base-from-origin — super has no `origin` to fetch from.

## Cross-reference

- The fixture builder: `tests/lib/fixture_local.sh` (`mkfixture_local` exports `FIXTURE_ROOT`, `FIXTURE_SUPER`)
- Assertion helpers: `tests/lib/assert.sh`
- Mutators used to construct conflict states: `tests/lib/mutators.sh` (`dirty`, `commit_one`, `force_diverge`, `checkout_main_in`)
- Top-level overview: [testing.md](testing.md)
