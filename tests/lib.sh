# Shared assertions for the helper_tools test suite.
# Sourced by tests/test_*.sh, which are run by tests/run.sh.

PASS=0; FAIL=0
: "${REPO:?REPO must be set by run.sh}"
BIN="$REPO/bin"

_green() { [[ -t 1 ]] && printf '\033[32m%s\033[0m' "$1" || printf '%s' "$1"; }
_red()   { [[ -t 1 ]] && printf '\033[31m%s\033[0m' "$1" || printf '%s' "$1"; }

ok()   { PASS=$((PASS+1)); printf '  %s %s\n' "$(_green PASS)" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  %s %s\n' "$(_red FAIL)" "$1"
         shift; for l in "$@"; do printf '         %s\n' "$l"; done; }

assert_eq() {  # desc expected actual
  if [[ $2 == "$3" ]]; then ok "$1"
  else bad "$1" "expected: [$2]" "actual:   [$3]"; fi
}

assert_contains() {  # desc haystack needle
  if [[ $2 == *"$3"* ]]; then ok "$1"
  else bad "$1" "needle missing: [$3]" "haystack: [${2:0:300}]"; fi
}

assert_not_contains() {  # desc haystack needle
  if [[ $2 != *"$3"* ]]; then ok "$1"
  else bad "$1" "should NOT contain: [$3]" "haystack: [${2:0:300}]"; fi
}

assert_rc() {  # desc expected_rc cmd...
  local desc=$1 want=$2; shift 2
  "$@" >/dev/null 2>&1; local got=$?
  if ((got == want)); then ok "$desc"
  else bad "$desc" "expected exit $want, got $got" "cmd: $*"; fi
}

assert_lines() {  # desc expected_count text
  local n; n=$(printf '%s' "$3" | grep -c . || true)
  if [[ $n == "$2" ]]; then ok "$1"
  else bad "$1" "expected $2 non-empty line(s), got $n" "text: [${3:0:300}]"; fi
}

# --- dx stub control -----------------------------------------------------
# Put the stub ahead of the real dx and give it a fixture directory.
use_dx_stub() {
  export DX_STUB_DIR="${1:?use_dx_stub needs a fixture dir}"
  export DX_STUB_CALLS="$DX_STUB_DIR/.calls"
  : > "$DX_STUB_CALLS"
  PATH="$REPO/tests/stub:$PATH"; export PATH
}
# grep -c prints "0" AND exits 1 when there are no matches, so `|| echo 0`
# would emit a second line. Swallow the status instead of adding output.
dx_call_count() {
  local n=0
  [[ -f ${DX_STUB_CALLS:-} ]] && n=$(grep -c . "$DX_STUB_CALLS" 2>/dev/null || true)
  printf '%s' "${n:-0}"
}

# Every test gets an isolated cache so runs cannot contaminate each other.
isolate_cache() { export DXURL_CACHE_DIR="${1:?}/dxurl-cache"; rm -rf "$DXURL_CACHE_DIR"; }
