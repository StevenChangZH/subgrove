# Demo recording for subgrove's README.
# Render with:  vhs demo.tape   ->  writes docs/demo.gif
# Needs https://github.com/charmbracelet/vhs and `subgrove` on $PATH.

Output docs/demo.gif

Set Shell "bash"
Set FontSize 18
Set Width 1200
Set Height 760
Set Padding 18
Set TypingSpeed 50ms

# --- off-camera setup ---
# Build the throwaway demo super (+ api, ui submodules) and step into it.
# demo-setup.sh symlinks THIS branch's `subgrove` into /tmp/subgrove-demo/bin,
# and we put that in front of $PATH so the recorded `subgrove` calls hit this
# branch's script (with `status`, etc.) — not whatever release the viewer has
# installed via Homebrew. One command per line so a slow step can't break the
# rest of the chain. The GIT_* exports give the recorded commits an identity
# without touching the viewer's global git config.
Hide
Type "bash scripts/demo-setup.sh" Enter
Sleep 1500ms
Type "export PATH=/tmp/subgrove-demo/bin:$PATH" Enter
Type "cd /tmp/subgrove-demo/super" Enter
Type "export GIT_AUTHOR_NAME='subgrove demo' GIT_AUTHOR_EMAIL=demo@subgrove.dev GIT_COMMITTER_NAME='subgrove demo' GIT_COMMITTER_EMAIL=demo@subgrove.dev" Enter
Type "clear" Enter
Show

# 1. Set up subgrove for this repo — detects submodules, writes .subgroverc.
Type "subgrove init -y" Sleep 500ms Enter
Sleep 3500ms

# init writes .subgroverc untracked + stages .gitignore — commit the setup
# (so the main super is clean for `merge`'s dirty-check later).
Type "git add -A && git commit -qm 'subgrove config'" Sleep 500ms Enter
Sleep 1500ms

# 2. Empty board: status reports the main row + "no feature worktrees yet".
Type "subgrove status" Sleep 400ms Enter
Sleep 3s

# 3. One worktree per feature — branches the parent AND both submodules.
Type "subgrove new dark-mode" Sleep 500ms Enter
Sleep 4s

# 4. Status now shows the worktree with api + ui touched, clean.
Type "subgrove status" Sleep 400ms Enter
Sleep 3500ms

# 5. Do real work in the ui submodule, then record the bump in the parent.
#    Both run in subshells so the recorded shell's cwd stays at the super.
Type "( cd .worktree/dark-mode/ui && echo 'dark mode' >> README.md && git commit -aqm 'dark theme' )" Sleep 500ms Enter
Sleep 1500ms
Type "( cd .worktree/dark-mode && git commit -aqm 'bump ui' )" Sleep 500ms Enter
Sleep 1500ms

# 6. Status: the feature is one commit ahead of main.
Type "subgrove status" Sleep 400ms Enter
Sleep 3500ms

# 7. Fast-forward main everywhere — ui merges, api skipped (no commits there).
Type "subgrove merge dark-mode" Sleep 500ms Enter
Sleep 4s

# 8. Status confirms main caught up — no longer ahead, propagation done.
Type "subgrove status" Sleep 400ms Enter
Sleep 4s
