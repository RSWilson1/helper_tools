# helper_tools shell integration.  Source this from ~/.bashrc:
#   source "$HOME/claude/helper_tools/config/shell.sh"

HELPER_TOOLS_DIR="${HELPER_TOOLS_DIR:-$HOME/claude/helper_tools}"

case ":$PATH:" in
  *":$HELPER_TOOLS_DIR/bin:"*) ;;
  *) PATH="$HELPER_TOOLS_DIR/bin:$PATH"; export PATH ;;
esac

# ripgrep only reads its config file if this points at it
[ -f "$HOME/.ripgreprc" ] && export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# --- dx shortcuts (the subcommands that dominate the shell history) ---
alias dxp='dx pwd'
alias dxls='dx ls -l'
alias dxsel='dx select'
alias dxrec='dxjob --recent'
alias dxfail='dxjob --failed'
alias dxrun='dxjob --running'

# dxcat: dx cat by object ID or by name in the current project
dxcat() {
  case "$1" in
    file-*|project-*:*) dx cat "$@" ;;
    *) local id; id=$(dxf "$1" --limit 1 2>/dev/null | head -1)
       [ -n "$id" ] && dx cat "$id" || { echo "dxcat: no match for '$1'" >&2; return 1; } ;;
  esac
}

# dxwhere: which project/folder does this object live in?
dxwhere() {
  [ -z "${1:-}" ] && { echo "usage: dxwhere OBJECT-ID" >&2; return 2; }
  dx describe --json "$1" 2>/dev/null \
    | jq -r '"\(.project)\t\(.folder // "-")\t\(.name // "-")"'
}
