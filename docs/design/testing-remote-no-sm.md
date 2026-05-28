# Remote tests — no-submodule tier

Tests under `tests/remote-no-sm/`. Run as part of `./tests/run.sh` (default); skip with `--local-only`. Gated on a single GitHub URL in `tests/config.sh`: `SUBGROVE_TEST_SUPER_NO_SM_URL`. Unlike the with-sm remote tier, there is no separate bootstrap script — `mkfixture_remote_no_sm` lazily pushes the baseline on its first call per machine.

The no-sm remote tier exercises wire-only paths the local no-sm tier can't reach:

- `subgrove new`'s fresh-base-from-origin (super origin/main advanced under us between fixture clone and `new`) on a no-sm super.
- `subgrove update`'s real `git fetch origin main` (the local no-sm tier always emits `warn: parent fetch failed` because the super has no `origin`).
- `subgrove merge push=true` **happy path** against a real remote (local-no-sm only covers the `'origin' does not appear` error path).
- `subgrove remove`'s "origin frozen" invariant after a prior `merge push=true`.

Companion to [testing-remote.md](testing-remote.md) (with-sm remote tier) and [testing-local-no-sm.md](testing-local-no-sm.md) (local no-sm tier).

56 scenarios across ten files: 48 single-case plus 8 matrix cells (4 + 2 + 2). The tier mirrors the local-no-sm tier on a wire-cloned super for paranoid coverage — every parameter-validation path, every refusal, and every dispatcher entry is re-exercised here so a future regression that only fires under "super was cloned from a real remote" is caught.

The parametric matrices are kept for structural symmetry with the with-sm remote tier even though they reduce to small cell counts (only one package — the parent — when there are no submodules):

- `test_new_matrix.sh` — 4 cells (`super_origin × local_main`)
- `test_update_matrix.sh` — 2 cells (`super_origin`)
- `test_merge_push_matrix.sh` — 2 cells (`super_origin`)

## Why this tier exists

The with-sm remote tier (`tests/remote/`) targets a super with two submodules; its scenarios assume `.gitmodules` and exercise per-submodule push order, peer-side commits on submodule mains, multi-package partial-failure half-states, etc. None of those translate to a no-sm super.

The local-no-sm tier (`tests/local-no-sm/`) covers most of subgrove's no-sm behavior, but its fixture has no `origin` on the super — every parent-fetch warns `parent fetch failed`, every `merge push=true` fails because `'origin' does not appear`. Four classes of behavior are therefore unreachable locally:

- The `new` parent-base-fresh-from-origin path.
- The `update` parent-fetch-succeeds path (and the resulting `refs/remotes/origin/main` advance).
- The `merge push=true` happy and non-FF paths against a real remote.
- The `remove`-doesn't-touch-origin invariant.

This tier fills that wire-only gap.

This is a deliberate reversal of an earlier deferral: the with-sm remote tier's design doc previously stated "the no-submodule tier has no remote counterpart … deferred until a concrete need arises." The need arose; the tier was added.

## The fixture

Single layer: `mkfixture_remote_no_sm` lazily bootstraps the baseline on first call, then per-test resets `main` back to the baseline tag.

### Per-call step order

Every `mkfixture_remote_no_sm` call runs these steps in order:

1. **Lock acquisition** (first call per script only). `git ls-remote $SUBGROVE_TEST_SUPER_NO_SM_URL refs/tags/subgrove-test-lock`. If present, abort with the remediation command. Otherwise push the tag and register an `EXIT`/`INT`/`TERM` trap to delete it. The lock is **distinct** from the with-sm remote tier's lock (they target different URLs); the two remote tiers can run sequentially in one `tests/run.sh` invocation without coordinating. Lock-first ordering means the bootstrap below runs serialized under the lock.
2. **Baseline-tag check / lazy bootstrap.** `git ls-remote $SUBGROVE_TEST_SUPER_NO_SM_URL refs/tags/subgrove-baseline`:
   - **Tag present:** skip bootstrap (the common case after first run).
   - **Tag missing:** bootstrap (see below).
3. **Reset main to baseline.** `git push --force <url> refs/tags/subgrove-baseline:refs/heads/main` — cheap on the wire (baseline objects already on the server; this is purely a ref move).
4. **Working clone.** `git clone <super-url>` into `tests/run/<ts>-remote-no-sm-<name>/super/`. Drop the `subgrove` symlink and pre-create `.worktree/`. No `git submodule update --init` step (there are no submodules).

### Lazy bootstrap (no separate init script)

When the baseline tag is missing (step 2 above), the fixture pushes a one-commit-plus-plumbing baseline (`README` + `.gitignore` containing `.worktree/` + `.subgroverc` with the same defaults as the local fixtures), tags it `subgrove-baseline`, then proceeds.

The bootstrap is non-interactive — no Y/N confirmation. This is the deliberate trade-off for skipping `init_remote.sh`: the consent gate moves from the script to the committed `tests/config.sh` (every URL is reviewed when added). As a typo backstop, the bootstrap **refuses to push to a non-empty remote**: it `ls-remote`s the URL and aborts if any ref exists *other than* our own `subgrove-test-lock` tag (which lock acquisition in step 1 has already pushed — so it's excluded from the emptiness test; otherwise a genuinely-empty fixture could never bootstrap). A real project (which has `main` or other refs) is therefore protected from a config-typo force-push; a fresh empty fixture proceeds.

The lock is **process-scoped** (same as the with-sm tier): a multi-iteration test acquires the lock on its first `mkfixture_remote_no_sm` call and keeps it across iterations; `cleanup_fixture_remote_no_sm` rms the local fixture dir but does NOT release the lock. Only the teardown trap at script exit releases.

### Teardown trap

On `EXIT`/`INT`/`TERM` of the test script:

1. `cd` to a known-existing directory first — the trap may fire after `cleanup_fixture_remote_no_sm` rm'd the test's cwd.
2. Delete every feature branch the script registered (via `register_feature_branch_no_sm <branch>`) from the no-sm super remote. Best-effort; errors swallowed.
3. Delete the lock tag. Inline-capture stderr so a real release failure surfaces a loud warning with a manual-recovery command instead of silently leaking. Non-zero rc on lock-release failure even if the test itself passed.

## Design invariants this tier guards

1. **`new` uses origin/main as the parent base on a no-sm super.** With super's origin/main ahead of stale local main, `subgrove new feat-X` creates `feat/feat-X` at the origin SHA, not the local SHA. Same invariant as the with-sm remote tier — pinned again here to catch a regression that would only fire when no submodules are present (e.g., a future check that gates origin-fetch on `.gitmodules` presence).

2. **`update`'s parent fetch actually succeeds on a no-sm super.** `git fetch origin main` returns clean (no `warn: parent fetch failed`), `refs/remotes/origin/main` advances when origin is ahead, and local `main` is never moved. The summary line `Updated 0 submodule main(s); 0 skipped` still fires (zero submodules to propagate to).

3. **`merge push=true` happy path on a no-sm super.** The Phase-2-only-touches-main-super contract still holds; the feat worktree is byte-identical after a successful push that advances super's origin. The local-no-sm tier cannot test this — its push always fails with `'origin' does not appear`.

4. **Push is FF-only and main-only on a no-sm super.** If super's origin/main has advanced beyond the local feat tip, `merge push=true` is rejected (no `--force`). The feat worktree is byte-identical even on the rejected-push path. The push moves only `main` — `feat/<name>` is never pushed to the remote.

5. **`remove` never reaches out to origin on a no-sm super.** Removing a worktree (with or without prior `merge push=true`) leaves the no-sm super's origin ref byte-for-byte where it was.

6. **User-data preservation (see [user-data-rules.md](user-data-rules.md)).** Across every no-sm remote scenario — happy, refuse, no-op — `snapshot_state` + `assert_state_eq` pin byte-identical preservation of:
   - `merge push=true`: feat worktree preserved on every outcome. Main super preserved on dirty/non-FF refusals.
   - `update`: main super + peer worktree preserved on every outcome. Update is ref-only.
   - `remove`: main super preserved. The named worktree disappears (the user's explicit opt-in); main super's working tree is byte-identical.
   - `new`: main super preserved. Only the gitignored `.worktree/<name>/` dir is added.

## Implementation notes

Three things to know before evolving this tier:

**No `init_remote.sh` integration.** The lazy bootstrap in the fixture replaces the separate one-time bootstrap script. This was a deliberate scope choice — the with-sm tier has a dedicated bootstrap script with a Y/N consent gate; the no-sm tier embeds the bootstrap inline without a prompt. The wire-safety contract is identical (don't point `SUBGROVE_TEST_SUPER_NO_SM_URL` at a real project) but the surface area for an accidental mis-target is one fewer command.

**The `_origin_main URL` helper is duplicated** across `test_merge_push.sh`, `test_merge_push_matrix.sh`, and `test_remove.sh` in this tier (and again in the with-sm tier's corresponding files). The duplication is intentional for now — each test file stays independently readable, and the helper is a one-liner. Update all copies together if the implementation needs to change.

**Matrices are small but kept for symmetry.** `test_update_matrix.sh` and `test_merge_push_matrix.sh` reduce to 2 cells each (`super_origin ∈ {even, ahead}` — no submodule axes). `test_new_matrix.sh` adds the `local_main` dimension for 4 cells, since `cmd_new`'s behavior depends on both origin and local main state. All three are kept for structural symmetry with the with-sm tier's 8- and 16-cell matrices — a reader who knows the with-sm matrix finds the same shape here.

**Per-case preservation pins are complete, not just on the headline cases.** Invariant 6 (and [user-data-rules.md](user-data-rules.md)) require the command's preserved location to be pinned on *every* case — success, refuse, and no-op — not only the golden path. This was audited case-by-case: `update`'s sentinel and dirty-peer cases snapshot main super + peer (not just the ref/pending-file checks); every `merge`/`merge push=true` case (including the dirty/non-FF refuses) snapshots the source feat worktree; every `remove` case (including the `-f` force variants and the multi-worktree case) snapshots main super; the success `merge` cases carry `assert_ancestor` for history correctness, not just tip-equality. The only refuse paths that deliberately skip the snapshot are `new`'s early-validation rejections (invalid name, not-gitignored, dir/branch collision, linked-worktree), which fire before `cmd_new`'s first mutation (`git worktree add`) — there is nothing to perturb, and the "no worktree/branch created, pre-existing content intact" checks already prove non-mutation.

## `test_new.sh` (10)

| Scenario | Setup | Asserts | Guards |
|---|---|---|---|
| Golden | fresh clone (origin/main == local main); `new feat-golden` | worktree dir + parent feat branch; HEAD on `feat/feat-golden`; parent base SHA == local `main`; `Submodule branching skipped (touch=none)` fires; `warn: parent fetch failed` does **NOT** fire (origin reachable); main super byte-identical pre/post | The happy path against a real remote. Invariants 1, 6. The negative-assert on `warn: parent fetch failed` distinguishes this tier from local-no-sm. |
| Super origin ahead | side-clone pushes a commit to super's main; then `new feat-up` | parent feat at the new origin SHA (not stale local); main super preserved | Invariant 1 — `new`'s fetch-and-rebase-on-origin logic on a no-sm super. |
| Super origin diverged | local commit on main (unpushed) + side-clone push to super's main; then `new feat-div` | parent feat at origin SHA; local main untouched at the local-commit SHA; main super preserved (status/diffs only — refs change is intentional) | Invariant 1 — origin freshness wins; local commit not bypassed silently in the worktree. |
| Branch collision after fresh clone | `new feat-x`, then `new feat-x` again | second `new` errs with "already exists"; main super AND existing feat worktree byte-identical across the refuse | The early-refuse path of `cmd_new` preserves both halves of the fixture. Invariant 6. |
| Linked-worktree refusal | `new feat-host`; invoke `new feat-from-linked` from inside `.worktree/feat-host/` | err mentioning "currently in a linked worktree" | `assert_main_worktree` fires on a remote-cloned super. Catches a regression where clone-vs-init shape changes the detection. |
| Invalid names rejected | call `new` with `.dotleading`, `-dashleading`, `spaces in name`, `ba/d`, empty | each errs with the kind-specific message; no `.worktree/<name>/` dirs left; no `feat/` branches left | `validate_name` independent of clone shape. Errors fire before fetch (no wire cost). |
| `.worktree/` not gitignored refused | empty `.gitignore`; `new feat-noignore` | err "not gitignored"; no worktree dir; no feat branch | `assert_worktrees_ignored` independent of clone shape. |
| Pre-existing worktree dir | pre-create `.worktree/feat-collide/marker`; `new feat-collide` | err "already exists"; no feat branch; pre-existing dir contents byte-identical | Dir-collision refusal independent of clone shape. |
| Pre-existing parent branch | `git branch feat/feat-pre main`; `new feat-pre` | err "branch ... already exists"; no worktree dir; pre-existing branch SHA unchanged | Branch-collision refusal independent of clone shape. |
| Dirty main super doesn't block | dirty parent edit; `new feat-x` | new succeeds; dirty edit preserved | `cmd_new` doesn't `require_clean`. Replicated here to catch a regression that only fires on a remote-cloned no-sm super. |

## `test_new_matrix.sh` (4 cells)

Parametric matrix: `super_origin ∈ {even, ahead}` × `local_main ∈ {at_baseline, with_local_commit}`. Pins that `cmd_new` uses `origin/main` as the feat base whenever it's fetchable, regardless of local main state.

| super_origin | local_main | Expected feat base |
|---|---|---|
| even | at_baseline | baseline (= local = origin) |
| even | with_local_commit | baseline (origin/main; local commit bypassed) |
| ahead | at_baseline | upstream SHA |
| ahead | with_local_commit | upstream SHA (local commit preserved on main, not used as base) |

Each cell: capture baseline + local SHAs, optionally push upstream, snapshot main super, run `new feat-x`, assert `feat/feat-x` at expected SHA, assert local main preserved, assert main super state preserved. Guards invariant 1 across the full state-tuple.

## `test_update.sh` (6)

| Scenario | Setup | Asserts | Guards |
|---|---|---|---|
| Super origin ahead | side-clone pushes to super origin; `update feat-su` | local main NOT moved (update is fetch-only at parent level); `refs/remotes/origin/main` advanced to the upstream commit; `Updated 0 submodule main(s); 0 skipped` fires; main super + peer worktree preserved | Invariant 2 — super-fetch updates only the remote-tracking ref, not local main, on a no-sm super. |
| No drift anywhere | no pushes; `update feat-n` | local main and origin/main unchanged; truthful zero-case summary; main super + peer preserved | True-no-op path against a reachable origin. |
| Nonexistent name | `update never-existed` | errs with "does not exist" | Doesn't silently no-op. |
| Sentinel ref never created in main super | `new feat-y`; `update feat-y` | `refs/heads/_update_sync`, `refs/_update_sync`, `refs/remotes/origin/_update_sync` all absent in main super after the call | Sentinel lives in per-submodule git dirs; with zero submodules, no sentinel anywhere in any of the parent's ref namespaces, regardless of clone-vs-init state. Mirrors local-no-sm's same invariant. |
| Pre-existing `_update_sync` in parent untouched | seed all three ref namespaces with `_update_sync`; `update feat-y` | each of the three refs still resolves to the same SHA afterward | Sentinel manipulation is scoped to per-submodule git dirs; an unrelated parent-level ref with the same name must not be clobbered. Same invariant as local-no-sm, pinned over the wire. |
| Doesn't require clean state | dirty edit in `.worktree/feat-y/`; `update feat-y` | succeeds (ref-only operation); dirty edit preserved | `cmd_update` is ref-only — same as the other tiers. |

## `test_update_matrix.sh` (2 cells)

Parametric matrix: per-cell `super_origin ∈ {even, ahead}`. Two cells:

- `super=even`: origin/main matches local main; nothing advances on the wire.
- `super=ahead`: side-clone pushes one commit; `refs/remotes/origin/main` advances to that SHA after `update`.

Each cell:

1. `mkfixture_remote_no_sm`; `new feat-x`.
2. Capture local main SHA.
3. For `ahead`: `push_to_origin_main` from a side-clone; capture the upstream SHA.
4. `snapshot_state` of main super + peer worktree.
5. Run `update feat-x`.
6. Assert: local main unchanged; for `ahead`, `refs/remotes/origin/main` at upstream SHA.
7. Assert: `Updated 0 submodule main(s); 0 skipped` in output.
8. Assert: main super + peer worktree byte-identical.

Guards invariants 2 and 6 across both origin-drift states. Kept for symmetry with the with-sm 16-cell matrix.

## `test_merge.sh` (7)

`push=false` (the default) over a reachable origin. Pins that `cmd_merge` does NOT silently contact origin when push=false even though origin is configured.

| Scenario | Setup | Asserts | Guards |
|---|---|---|---|
| Golden (push=false default) | parent commit in feat-g; `merge feat-g` | parent main FF'd locally; super origin **unchanged**; `Fast-forwarding parent main` and `Push skipped (push=true to enable)` both fire; feat worktree byte-identical | Default push=false MUST NOT touch origin, even when reachable. Invariant 6 (worktree preserved). |
| Multi-commit feat | 3 commits on feat-mc; `merge feat-mc` | every feat commit is an ancestor of main (`assert_ancestor` per commit); super origin unchanged | History correctness — FF preserves every commit. Catches a future regression from `--ff-only` to `--squash` even when origin is reachable. |
| Nothing to merge | `new feat-n` (no commits); `merge feat-n` | "Nothing to merge"; refs unchanged; main super + feat worktree state preserved; super origin unchanged; `Push skipped (push=true to enable)` (push=false variant) | Phase-0 filter short-circuits without mutating anything. |
| Non-FF parent | commit on feat + commit directly on main super; `merge feat-x` | err "parent main is not ancestor of feat/feat-x (non-FF)"; main SHA unchanged; main super state preserved; super origin unchanged | Parent FF check fires; no half-state, no wire touch. |
| Nonexistent branch | `merge never-existed` | err "does not exist" | Doesn't try to merge a non-existent ref. |
| Dirty parent (dst) refused | feat commit + dirty in main super; `merge feat-x` | err "main worktree (parent, dst) has uncommitted"; state preserved; `Fast-forwarding parent main` ABSENT; super origin frozen | `require_clean` on the dst parent fires before merge mutation, push not attempted. |
| Two peer worktrees | `new feat-x` + `new feat-y`; commit on x; `merge feat-x` | `Propagating new main to peer worktrees` ABSENT; `Moving main forward in main worktree's submodules` ABSENT; Phase 1 ran (`Fast-forwarding parent main` fires); feat-y worktree byte-identical | Peer-propagation info lines must not fire on a no-sm super. Invariant 6 — peer worktree preserved. |

## `test_merge_push.sh` (6)

`push=true` against a reachable origin.

| Scenario | Setup | Asserts | Guards |
|---|---|---|---|
| Golden parent | parent commit in feat-g; `merge feat-g push=true` | super origin advances to feat tip; feat worktree byte-identical pre/post | Invariant 3 — happy push against a real remote on a no-sm super. The local-no-sm equivalent can only reach the error path. Invariant 6. |
| Nothing to push | `new feat-n` (no commits); `merge feat-n push=true` | "Nothing to merge\|Push skipped" in output; super origin unchanged; main super + feat worktree byte-identical | The Phase-0 filter short-circuits push too. Invariant 6 (main super preserved). |
| Non-FF super | parent commit; side-clone advances super origin; `merge feat-nff push=true` | non-zero rc; super origin stays at upstream; feat worktree byte-identical even though Phase 2 + push happened | Invariant 4 — push refused, no force. Invariant 6 — user's WIP preserved regardless of push outcome. |
| Dirty parent dst | parent commit in feat-d + dirty edit in main super; `merge feat-d push=true` | non-zero rc; "main worktree (parent, dst) has uncommitted" err; main super byte-identical (dirty edit preserved); super origin frozen on refuse | The Phase-1 dirty-refuse path on a no-sm super doesn't reach the push phase. Invariant 6. |
| Multi-commit feat | 3 commits on feat-mc; `merge feat-mc push=true` | every feat commit is an ancestor of main (`assert_ancestor` per commit); super origin = feat tip; feat worktree preserved | History correctness over real push. Catches `--ff-only` → `--squash` regression on the push path. |
| Feat branch NOT pushed | parent commit; `merge feat-fnp push=true` | super origin = feat tip; `refs/heads/feat/feat-fnp` does **NOT** appear in `git ls-remote` | Push moves only `main`, never `feat/<name>`. Catches a regression where future code accidentally pushes feat refs alongside main. |

## `test_merge_push_matrix.sh` (2 cells)

Parametric matrix: `super_origin ∈ {even, ahead}`. Two cells:

- `super=even`: push succeeds; origin advances to feat tip.
- `super=ahead`: push rejected (non-FF); origin stays at upstream.

Each cell:

1. `mkfixture_remote_no_sm`; `new feat-x`; parent commit.
2. For `ahead`: push a third-party commit to super's main via `push_to_origin_main`.
3. Capture local feat tip and pre-merge origin SHA.
4. `snapshot_state` of the feat worktree.
5. Run `merge feat-x push=true`; capture rc.
6. For `even`: rc==0, origin at feat tip. For `ahead`: rc!=0, origin at upstream.
7. Feat worktree byte-identical.

Guards invariants 3, 4, 6. Kept for symmetry with the with-sm 8-cell matrix.

## `test_remove.sh` (8)

| Scenario | Setup | Asserts | Guards |
|---|---|---|---|
| Remove without prior push | `new feat-rmnp`; parent commit; `remove feat-rmnp -f` (force: dirty parent isn't dirty here, but `-f` is harmless) | worktree gone; super origin unchanged; main super byte-identical pre/post | Invariant 5 — `remove` never touches origin. Invariant 6 — main super's working tree preserved. |
| Remove after merge push=true | `new feat-rmap`; parent commit; `merge feat-rmap push=true`; snapshot origin SHA; `remove feat-rmap` | worktree gone; super origin SHA (advanced via merge push) unchanged by the subsequent remove; main super byte-identical post-remove; parent feat branch retained locally | Invariant 5 — origin frozen across remove. Invariant 6 — main super preserved. The lifecycle.md "branches retained" contract verified over real-wire push on a no-sm super. |
| Dirty parent worktree refused | dirty edit in `.worktree/feat-x/`; `remove feat-x` | err "feature worktree (parent) has uncommitted"; worktree intact; specific pending edit preserved; state snapshot preserved; super origin unchanged on refuse | `require_clean` on the parent. Origin frozen on refuse. |
| `-f` short flag overrides dirty | dirty + `-f` | worktree gone; parent feat branch retained at the original SHA | `-f` discards dirty edits (explicit opt-in) but preserves the committed branch. |
| `--force` long flag alias | dirty + `--force` | same as `-f` | Long alias. |
| `force=true` key-value alias | dirty + `force=true` | same as `-f` | Key=value alias. |
| Nonexistent name | `remove never-existed` | err "does not exist" | Doesn't silently no-op. |
| Multi-worktree (remove middle, others survive) | `new feat-a` + `new feat-b` + `new feat-c`; `remove feat-b` | feat-b gone; feat-a and feat-c byte-identical; parent feat-b branch retained; sibling branches retained; super origin unchanged | `remove` is correctly scoped: targets only the named worktree. Three worktrees test both before- and after-target positions relative to the removed one. |

## `test_list.sh` (8)

Dispatcher and `subgrove list` are independent of origin, but every entry is exercised over the wire to catch any future code path that branches on clone-vs-init state (e.g., help text that probes `refs/remotes/`). Mirrors `tests/local-no-sm/test_list.sh` on a wire-cloned super.

| Scenario | Asserts |
|---|---|
| `list` after `new feat-a feat-b` | output contains `[feat/feat-a]` and `[feat/feat-b]` |
| `ls` alias | same effect as `list` |
| `subgrove` (no args) | prints usage; exit 0 |
| `subgrove help` | prints usage; exit 0 |
| `subgrove bogus-cmd` | exit non-zero; prints usage |
| `rm` alias | same effect as `remove` |
| `subgrove -h` | prints usage; exit 0 |
| `subgrove --help` | prints usage; exit 0 |

## `test_linked_worktree.sh` (3)

Each of `merge`, `remove`, `update` invoked from inside `.worktree/feat-host/` must err with the "currently in a linked worktree" message. Mirrors `tests/local-no-sm/test_linked_worktree.sh` on a wire-cloned super. State-preservation snapshot covers only the parent.

| Scenario | Asserts | Guards |
|---|---|---|
| `merge` from linked worktree | err "currently in a linked worktree"; parent state preserved | `cmd_merge`'s `assert_main_worktree` fires on a remote-cloned no-sm super. |
| `remove` from linked worktree | same | `cmd_remove`'s `assert_main_worktree` fires. |
| `update` from linked worktree | same | `cmd_update`'s `assert_main_worktree` fires. |

## Tests intentionally NOT in `tests/remote-no-sm/`

These paths are either covered elsewhere or genuinely N/A on a no-sm super:

- **All per-submodule scenarios** (peer-side commits on submodule mains, per-package push order, partial-failure half-states, sm-a-ahead-while-sm-b-clean, etc.). No submodules → no scenario. The with-sm tier (`tests/remote/`) covers these.
- **`merge push=true` partial-failure half-state.** Requires multiple packages. N/A on a no-sm super.
- **The `merge` dirty-refuse matrix from the with-sm tier.** Exponential in `(parent, sm-a, sm-b) × (staged, unstaged)`; the no-sm super collapses to the parent axes only, which the `merge_dirty_parent` (push=false) and `merge_push_dirty` (push=true) single-case scenarios already cover.
- **Build failure keeps the worktree.** A failing build leaves the worktree (and any commits) in place rather than rolling it back — local execution with no wire dimension. Already covered by `tests/local-no-sm/test_new.sh::new_build_fail_keeps`; the behavior doesn't depend on whether the super was cloned vs init'd.
- **Origin ahead by *many* commits.** The single-commit `super_origin_ahead` scenario proves the fetch+rebase logic works; an N-commit variant adds no new code path.

## Cross-reference

- The fixture builder: `tests/lib/fixture_remote_no_sm.sh` (`mkfixture_remote_no_sm` exports `FIXTURE_ROOT`, `FIXTURE_SUPER`; `register_feature_branch_no_sm` enrolls a branch in the teardown cleanup; `cleanup_fixture_remote_no_sm` rms the local fixture but keeps the lock for subsequent iterations).
- Push-side helpers: `tests/lib/mutators.sh::push_to_origin_main` and `push_n_to_origin_main` (shared with the with-sm tier).
- Assertion helpers: `tests/lib/assert.sh` — same set as the other tiers.
- Configuration: `tests/config.sh` (committed; maintainer fills in `SUBGROVE_TEST_SUPER_NO_SM_URL` alongside the with-sm URLs).
- With-sm remote companion: [testing-remote.md](testing-remote.md).
- Local no-sm companion: [testing-local-no-sm.md](testing-local-no-sm.md).
- Top-level overview: [testing.md](testing.md).
- User-data preservation rules these tests pin: [user-data-rules.md](user-data-rules.md).
