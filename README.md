# subgrove

Parallel feature development for a git superproject with submodules. One feature, one parent worktree, isolated submodule git dirs, automatic propagation of merges across linked worktrees.

A single shell script. Zero install. Readable in fifteen minutes.

## Is this for you?

`subgrove` sits at the intersection of three properties:

1. **Parent worktree per feature** — each in-progress feature is a separate directory on disk; switching is `cd`, not `git checkout`.
2. **Per-worktree-isolated submodule git dirs** — git's default for submodules under linked worktrees, with all the consequences that follow.
3. **Cross-worktree merge propagation** — merging in one worktree updates every other worktree's view of `main` for each affected submodule.

If your repo has no submodules, a single-repo worktree manager like [gwq](https://github.com/d-kuro/gwq) or [grove](https://github.com/DonKoko/grove) is a cleaner fit. If your world is polyrepo (many independent repos, no parent), [Google `repo`](https://source.android.com/docs/setup/reference/repo) or [gita](https://github.com/nosarthur/gita) covers that. If you have a superproject + submodules and want a daily sync rather than per-feature worktrees, [sync_submodules](https://github.com/shibuido/sync_submodules) is the closest thing.

What's left after subtracting those — _per-feature worktree × isolated submodule git dirs × cross-worktree propagation_ — is the gap subgrove fills. See [docs/design/prior-art.md](docs/design/prior-art.md) for the full survey.

## Install

Drop `subgrove` at your superproject root (the script expects to live next to your `.gitmodules`):

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/subgrove/main/subgrove -o subgrove
chmod +x subgrove
```

Copy [`.subgroverc.example`](.subgroverc.example) to `.subgroverc` next to it and edit the values for your project:

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/subgrove/main/.subgroverc.example -o .subgroverc
$EDITOR .subgroverc
```

Add `.worktree/` to your superproject's `.gitignore` — subgrove refuses to run otherwise.

## Quickstart

```bash
./subgrove new my-feature             # create .worktree/my-feature/, branch feat/my-feature
cd .worktree/my-feature
# ... do work, commit ...

./subgrove merge my-feature           # FF-merge to main everywhere it needs to land
./subgrove merge my-feature push=true # ... and push origin/main

./subgrove remove my-feature          # tear down the worktree (branches retained)
```

## Commands

| Command                               | Purpose                                                           |
| ------------------------------------- | ----------------------------------------------------------------- |
| `subgrove new <name>`                 | Create a worktree; branch parent + submodules; run `BUILD_CHAIN`. |
| `subgrove new <name> touch=<sm>,<sm>` | Branch only the listed submodules.                                |
| `subgrove new <name> touch=none`      | Parent-only branch; submodules detached.                          |
| `subgrove new <name> build=false`     | Skip `BUILD_CHAIN`.                                               |
| `subgrove merge <name>`               | FF-merge feature branch → `main`, propagate to peer worktrees.    |
| `subgrove merge <name> push=true`     | ... and push to `origin`.                                         |
| `subgrove update <name>`              | Catch a peer worktree up to `origin/main` without merging.        |
| `subgrove remove <name>`              | Remove a worktree (refuses if dirty).                             |
| `subgrove remove <name> -f`           | Force-remove, discarding uncommitted work.                        |
| `subgrove list`                       | List worktrees.                                                   |
| `subgrove help`                       | Show usage.                                                       |

Long-form reference: [docs/usage.md](docs/usage.md).

## Configuration

`.subgroverc` at the superproject root:

```bash
BUILD_CHAIN=(libfoo libbar)              # submodules to init+build after `new`
BUILD_CMD="./init.sh && ./build.sh"      # build command per BUILD_CHAIN module
COPY_TO_NEW_WORKTREE=(.claude)           # items copied from main → new worktrees
BRANCH_PREFIX="feat/"                    # feature branch prefix
```

See [.subgroverc.example](.subgroverc.example).

## Design

The script's complexity is a direct consequence of holding three properties simultaneously (per-feature parent worktree, per-worktree-isolated submodule git dirs, cross-worktree main propagation). Each design doc walks through one of those decisions:

- [motivation.md](docs/design/motivation.md) — goals, the submodule git-dir isolation constraint, why parent-worktree-per-feature
- [merge.md](docs/design/merge.md) — two-phase merge + peer propagation
- [update.md](docs/design/update.md) — the `_update_sync` sentinel
- [lifecycle.md](docs/design/lifecycle.md) — `new` (rollback, `--reference`) and `remove`
- [trade-offs.md](docs/design/trade-offs.md) — alternatives considered & rejected
- [implementation-notes.md](docs/design/implementation-notes.md) — cross-cutting invariants
- [prior-art.md](docs/design/prior-art.md) — survey of related tools and the gap subgrove fills

## License

MIT. See [LICENSE](LICENSE).
