# Prior art and related tools

A scan of the open-source landscape didn't turn up a tool that occupies the same niche: *parent worktree per feature × N coordinated submodules × cross-worktree merge propagation*. The adjacent ecosystems split into three groups, each covering a different slice of the problem.

## Single-repo worktree managers

Plenty of single-file CLIs that wrap `git worktree add/remove/list` with a nicer UX. None treat submodules as a first-class concept; the recurring framing is "parallel AI agents on independent branches", with worktrees assumed independent.

- [d-kuro/gwq](https://github.com/d-kuro/gwq) — fuzzy-finder TUI, per-worktree `setup_commands`, tmux integration. Submodules unmentioned; init would need to be a custom setup command.
- [ben-rogerson/git-worktree-toolbox](https://github.com/ben-rogerson/git-worktree-toolbox) — MCP-tool set (`list/new/archive/go/changes/grab/pr/...`). Submodules unmentioned.
- [omerhadari/gwt](https://github.com/omerhadari/gwt), [gko/gwt](https://github.com/gko/gwt), [DonKoko/grove](https://github.com/DonKoko/grove), [ahmadawais/gwtree](https://github.com/ahmadawais/gwtree), [mikko-kohtala/git-worktree-cli](https://github.com/mikko-kohtala/git-worktree-cli), [sotarok/gw](https://github.com/sotarok/gw) — same niche, varying polish.
- [pnpm `worktree:new`](https://pnpm.io/next/git-worktrees) — worktree bootstrapper baked into pnpm. Single-repo focus.
- [nanasess/git-worktree-manager](https://github.com/nanasess/git-worktree-manager) — bulk worktree management for projects with multiple repos; worktrees placed outside the project tree. Doesn't model a parent-with-submodules.

If your project is single-repo, any of `gwq` / `grove` would be a clean drop-in.

## Multi-repo coordinators

Different topology — *many independent repos* managed by a manifest, no worktrees-per-feature, no "parent records submodule SHAs" concept because there is no parent.

- [Google `repo`](https://source.android.com/docs/setup/reference/repo) and forks [esrlabs/git-repo](https://github.com/esrlabs/git-repo), [GatorQue/git-repo-flow](https://github.com/GatorQue/git-repo-flow), [wavecomp/git-repo](https://github.com/wavecomp/git-repo) — manifest-driven multi-repo workflow.
- [nosarthur/gita](https://github.com/nosarthur/gita) — fan-out commands over many repos.

Useful when the world *is* polyrepo. Doesn't apply when a parent submodule pointer is the source of truth for component versions.

## Submodule sync tools

Closer in spirit but not worktree-based.

- [shibuido/sync_submodules](https://github.com/shibuido/sync_submodules) — Bash script for a "superrepo + submodules" team workflow. Does pull/push of superrepo + every submodule with conflict detection and FF-only safety. **Explicitly does not** model worktrees, coordinated feature branching across parent + submodules, or parallel worktree state. Model is "everyone shares one checkout, run sync daily".

## Comprehensive guides (no full tool)

- [ashwch — "Git Worktrees: From Zero to Hero"](https://gist.github.com/ashwch/946ad983977c9107db7ee9abafeb95bd) walks through `worktree + submodules`, observes that each linked worktree gets its own submodule copy, and references two helper scripts (`create_worktree.py`, `update_submodules.py`) — but the gist documents the pattern rather than packaging a full lifecycle manager. No merge-propagation across worktrees.

## Gap analysis: what subgrove does that others don't

After the survey, these design points appear to be unusual-to-novel in combination, rather than borrowed from a known tool:

1. **Coordinated parent + per-submodule feature branching at `new` time** (`touch=` selects which submodule git dirs get a `<prefix><name>` ref, anchored at the parent's just-fetched recorded SHA). Single-repo tools have nothing to coordinate; multi-repo tools don't have a parent to anchor to.
2. **`git submodule update --init --reference <main-worktree-sm-gitdir>`** so new worktrees share object DBs with the main worktree via `objects/info/alternates`. None of the surveyed tools wire `--reference` into submodule init; most accept the per-worktree duplicate-clone cost.
3. **Merge-time peer propagation that writes the FF'd main into every *other* linked worktree's submodule git dir.** Other tools don't acknowledge that linked-worktree submodule git dirs are isolated, let alone propagate across them.
4. **`cmd_update`'s transient `refs/heads/_update_sync` sentinel** to FF a peer's submodule main from main worktree's `refs/remotes/origin/main` *without* `git push` and *without* working-tree mutation. The reason this needs a sentinel — that `upload-pack` only advertises `refs/heads/*` and `refs/tags/*` — is a constraint none of the surveyed tools have to grapple with because none try to do the equivalent operation.
5. **Two-phase merge with FF validation before any mutation, plus an `EXIT` rollback trap on `cmd_new`.** Lifecycle hygiene that the comparable scripts don't package.

The honest summary: the script's complexity isn't from over-engineering — it's a consequence of holding three properties simultaneously (per-feature parent worktree, per-worktree-isolated submodule git dirs, cross-worktree main propagation). The tools that drop *any one* of those properties have a much simpler implementation than this one needs to be.

## Positioning: niche dominance, not "superset"

A recurring temptation is to market subgrove as a *superset* of the tools above — "it does everything they do, plus submodules." Recorded here so the framing doesn't drift, because that claim is false on three counts:

- **The topologies are mutually exclusive.** gita and Google `repo` are polyrepo coordinators: many independent repos, no parent. subgrove's entire model assumes a superproject whose gitlinks are the source of truth for component SHAs — the assumption that makes FF-merge and peer propagation work. A tool cannot simultaneously be "the parent records the SHAs" and "there is no parent."
- **A literal superset would need runtimes subgrove forbids.** Matching gwq's fuzzy TUI, `repo`'s manifest engine, gita's async fan-out, and git-worktree-toolbox's MCP server means shipping a TUI, a manifest parser, and an MCP server — i.e. abandoning "a single distributed shell script, no runtime beyond bash" (CLAUDE.md). Even today, in the one overlapping domain (plain worktree create/list/remove), subgrove is a *subset* of gwq, not a superset.
- **Breadth dilutes the only thing that makes it findable.** subgrove's wedge is that it is the *sole* tool that touches submodules. Claiming general-worktree-manager parity invites comparison on general-worktree-manager terms, where a Go binary with a fuzzy finder wins; "does everything" reads as "best at nothing."

The defensible claim, scoped to the niche: *for a superproject with submodules*, subgrove **consolidates** what you would otherwise assemble from a worktree manager's create/list/remove **plus** coordinated submodule branching / FF-merge / propagation **plus** submodule sync — everything those tools do *for this case*, and the part all of them skip. That is niche dominance with an honest consolidation claim, not a superset of every tool.
