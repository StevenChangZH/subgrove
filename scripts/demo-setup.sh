#!/usr/bin/env bash
# Builds a throwaway demo superproject (+ two submodules, api & ui) under
# ${SUBGROVE_DEMO_DIR:-/tmp/subgrove-demo} so `demo.tape` (vhs) can record a
# realistic subgrove session. Idempotent — wipes and rebuilds each run.
# Demo tooling only; not shipped or installed.
#
# Intentionally leaves the super UN-CONFIGURED for subgrove — no `.subgroverc`,
# no `.gitignore` entry, no `.worktree/` dir. The first recorded command in
# `demo.tape` is `subgrove init -y`, and we want it doing its real job
# (detecting submodules, writing the config), not no-op'ing on a pre-baked
# repo.
set -eo pipefail

DEMO="${SUBGROVE_DEMO_DIR:-/tmp/subgrove-demo}"
# user.* so commits work without global git config; protocol.file.allow so the
# file:// submodules can be cloned (git >= 2.38 blocks file:// by default).
export GIT_CONFIG_PARAMETERS="'protocol.file.allow=always' 'user.email=demo@subgrove.dev' 'user.name=subgrove demo'"

rm -rf "$DEMO"
mkdir -p "$DEMO"

# Symlink the repo's `subgrove` into a fixed bin dir so `demo.tape` can put
# one stable PATH entry in front — guarantees the recorded `subgrove` calls
# hit THIS branch's script (with `status`, etc.) rather than whatever release
# the viewer has installed via Homebrew.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$DEMO/bin"
ln -sf "$REPO_ROOT/subgrove" "$DEMO/bin/subgrove"

_init_repo() {
    local path="$1" label="$2"
    git init --quiet "$path"
    (
        cd "$path"
        git symbolic-ref HEAD refs/heads/main
        printf '# %s\n' "$label" > README.md
        git add README.md
        git commit --quiet -m "init: $label"
    )
}

_init_repo "$DEMO/api" "api service"
_init_repo "$DEMO/ui"  "ui app"

git init --quiet "$DEMO/super"
(
    cd "$DEMO/super"
    # Bake protocol.file.allow into the repo so the demo runs without env vars.
    git config protocol.file.allow always
    git symbolic-ref HEAD refs/heads/main
    printf '# webapp (subgrove demo superproject)\n' > README.md
    git add README.md
    git commit --quiet -m "init: webapp"

    git submodule add --quiet "file://$DEMO/api" api
    git submodule add --quiet "file://$DEMO/ui"  ui
    git commit --quiet -m "add submodules: api, ui"
    ( cd api && git checkout --quiet -B main )
    ( cd ui  && git checkout --quiet -B main )
)

echo "demo super: $DEMO/super"
