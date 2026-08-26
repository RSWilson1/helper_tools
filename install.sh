#!/usr/bin/env bash
#
# install.sh - wire helper_tools into the shell.
#
# Safe to re-run: every step checks whether it has already been done, and
# anything it replaces is backed up with a .bak-<timestamp> suffix.
#
set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STAMP=$(date +%Y%m%d-%H%M%S)
DRY=0
FIX_GIT=0

for arg in "$@"; do
  case $arg in
    -n|--dry-run)     DRY=1 ;;
    --fix-gitconfig)  FIX_GIT=1 ;;
    -h|--help)
      cat <<'USAGE_TEXT'
usage: ./install.sh [-n|--dry-run] [--fix-gitconfig]

  Adds helper_tools/bin to PATH via ~/.bashrc, installs the ripgrep config
  to ~/.ripgreprc, and reports any recommended CLI tools that are missing.

  -n, --dry-run      show what would change, change nothing
      --fix-gitconfig  also collapse duplicate [user] name entries in
                       ~/.gitconfig (backed up first)
USAGE_TEXT
      exit 0 ;;
    *) echo "install.sh: unknown argument '$arg' (try --help)" >&2; exit 2 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
act()  { if ((DRY)); then printf '  [dry-run] %s\n' "$*"; else printf '  %s\n' "$*"; fi; }
head_() { printf '\n== %s\n' "$*"; }

# ------------------------------------------------------------------ 1. PATH
head_ "shell integration"
SRC_LINE="source \"$REPO/config/shell.sh\""
BASHRC="$HOME/.bashrc"
if [[ -f $BASHRC ]] && grep -Fq "$REPO/config/shell.sh" "$BASHRC"; then
  say "already sourced from ~/.bashrc"
else
  act "appending to ~/.bashrc: $SRC_LINE"
  if ((DRY == 0)); then
    { printf '\n# helper_tools (%s)\n%s\n' "$STAMP" "$SRC_LINE"; } >> "$BASHRC" \
      || { echo "  FAILED to write $BASHRC" >&2; exit 1; }
  fi
fi

# ------------------------------------------------------------- 2. ripgreprc
head_ "ripgrep config"
RC="$HOME/.ripgreprc"
if [[ -f $RC ]] && cmp -s "$RC" "$REPO/config/ripgreprc"; then
  say "~/.ripgreprc already matches config/ripgreprc"
else
  if [[ -s $RC ]]; then
    act "backing up existing ~/.ripgreprc -> ~/.ripgreprc.bak-$STAMP"
    ((DRY)) || cp -p "$RC" "$RC.bak-$STAMP"
  fi
  act "installing config/ripgreprc -> ~/.ripgreprc"
  ((DRY)) || cp "$REPO/config/ripgreprc" "$RC"
  say "note: rg only reads it when RIPGREP_CONFIG_PATH is set (config/shell.sh does that)"
fi

# -------------------------------------------------------------- 3. gitconfig
head_ "git config"
mapfile -t NAMES < <(git config --global --get-all user.name 2>/dev/null)
if ((${#NAMES[@]} > 1)); then
  say "~/.gitconfig has ${#NAMES[@]} [user] name entries: ${NAMES[*]}"
  say "git uses the last one (\"${NAMES[-1]}\"); the others are dead weight"
  if ((FIX_GIT)); then
    act "collapsing to \"${NAMES[-1]}\" (backing up ~/.gitconfig first)"
    if ((DRY == 0)); then
      cp -p "$HOME/.gitconfig" "$HOME/.gitconfig.bak-$STAMP" 2>/dev/null
      git config --global --unset-all user.name
      git config --global user.name "${NAMES[-1]}"
    fi
  else
    say "re-run with --fix-gitconfig to collapse them"
  fi
else
  say "user.name is unambiguous (${NAMES[0]:-unset})"
fi

# --------------------------------------------------------- 4. missing tools
head_ "recommended tools"
declare -A HINT=(
  [fzf]="apt install fzf   # Ctrl-R history search - the biggest single win"
  [fd]="apt install fd-find (binary is 'fdfind' on Debian/Ubuntu)"
  [bat]="apt install bat    (binary is 'batcat' on Debian/Ubuntu)"
  [delta]="cargo install git-delta   # readable git diffs"
  [jq]="apt install jq     # REQUIRED by dxurl"
)
missing=0
for t in fzf fd bat delta jq; do
  if command -v "$t" >/dev/null 2>&1; then
    say "$t: present"
  else
    say "$t: MISSING - ${HINT[$t]}"
    missing=$((missing + 1))
  fi
done

# ------------------------------------------------------------------- 5. deps
head_ "hard requirements"
for t in dx jq bash find; do
  if command -v "$t" >/dev/null 2>&1; then
    say "$t: ok"
  else
    say "$t: MISSING - the dx* tools need it"
  fi
done

printf '\n'
if ((DRY)); then
  echo "Dry run only - nothing was changed."
else
  echo "Done. Start a new shell, or: source $REPO/config/shell.sh"
fi
((missing)) && echo "$missing recommended tool(s) missing (see above)."
exit 0
