# bash completion for subgrove.  Install: source this file from ~/.bashrc, or
# let Homebrew drop it in (bash_completion.install). Static — not generated
# from lib/, so build.sh doesn't touch it.
#
# Completes: subcommands; existing worktree names for the verbs that take one
# (merge/update/remove/status); submodule paths for `touch=`; true/false for
# build=/push=/force=. macOS bash 3.2 compatible.

# Existing feature-worktree names (basenames under WORKTREES_DIR). Always
# invoked inside a $(...) subshell below, so sourcing the repo's .subgroverc
# here cannot leak vars (WORKTREES_DIR/BUILD_*/…) into the interactive shell.
# WORKTREES_DIR defaults to .worktree and is overridden by .subgroverc,
# matching how subgrove itself resolves it.
_subgrove_worktrees() {
    local root wt WORKTREES_DIR=".worktree"
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
    [[ -n "$root" ]] || return 0
    [[ -f "$root/.subgroverc" ]] && . "$root/.subgroverc" 2>/dev/null
    [[ -d "$root/$WORKTREES_DIR" ]] || return 0
    for wt in "$root/$WORKTREES_DIR"/*/; do
        [[ -d "$wt" ]] || continue
        wt="${wt%/}"
        printf '%s\n' "${wt##*/}"
    done
}

# Submodule paths from the superproject's .gitmodules (same parser subgrove uses).
_subgrove_submodules() {
    local root
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
    [[ -n "$root" && -f "$root/.gitmodules" ]] || return 0
    git config --file "$root/.gitmodules" --get-regexp 'submodule\..*\.path' 2>/dev/null \
        | awk '{print $2}'
}

_subgrove() {
    local cur sub
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"

    # Position 1: the subcommand.
    if [[ "$COMP_CWORD" -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "init new merge update remove status list help version" -- "$cur") )
        return 0
    fi

    sub="${COMP_WORDS[1]}"

    # key=value flags (position-independent: they can follow the name).
    case "$cur" in
        touch=*) COMPREPLY=( $(compgen -W "$(_subgrove_submodules) all none" -P "touch=" -- "${cur#touch=}") ); return 0 ;;
        build=*) COMPREPLY=( $(compgen -W "true false" -P "build=" -- "${cur#build=}") ); return 0 ;;
        push=*)  COMPREPLY=( $(compgen -W "true false" -P "push="  -- "${cur#push=}")  ); return 0 ;;
        force=*) COMPREPLY=( $(compgen -W "true false" -P "force=" -- "${cur#force=}") ); return 0 ;;
    esac

    # Second positional for the verbs that take an existing worktree name.
    if [[ "$COMP_CWORD" -eq 2 ]]; then
        case "$sub" in
            merge|update|remove|status)
                COMPREPLY=( $(compgen -W "$(_subgrove_worktrees)" -- "$cur") )
                return 0 ;;
        esac
    fi

    # Otherwise suggest the flags each subcommand accepts.
    case "$sub" in
        new)    COMPREPLY=( $(compgen -W "touch= build=" -- "$cur") ) ;;
        merge)  COMPREPLY=( $(compgen -W "push=" -- "$cur") ) ;;
        remove) COMPREPLY=( $(compgen -W "-f force=" -- "$cur") ) ;;
    esac
    return 0
}

complete -F _subgrove subgrove
