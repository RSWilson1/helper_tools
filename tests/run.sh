#!/usr/bin/env bash
# Runs every tests/test_*.sh. Exits non-zero if any assertion failed.
set -uo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd); export REPO

only=${1:-}
total_pass=0; total_fail=0; files=0

for t in "$REPO"/tests/test_*.sh; do
  [[ -n $only && $t != *"$only"* ]] && continue
  files=$((files+1))
  printf '\n== %s\n' "${t##*/}"
  # each file runs in its own shell so exports cannot leak between them
  out=$(bash "$t" 2>&1); echo "$out"
  p=$(grep -c '^  PASS\|^  .*PASS' <<<"$out" || true)
  f=$(grep -c '^  FAIL\|^  .*FAIL' <<<"$out" || true)
  total_pass=$((total_pass + p)); total_fail=$((total_fail + f))
done

printf '\n---------------------------------------------\n'
printf '%d file(s): %d passed, %d failed\n' "$files" "$total_pass" "$total_fail"
((total_fail == 0)) || exit 1
