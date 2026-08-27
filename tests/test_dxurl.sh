#!/usr/bin/env bash
set -uo pipefail
source "$REPO/tests/lib.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/describe"
use_dx_stub "$TMP"
isolate_cache "$TMP"

PJ=project-J9yxvY04kjB0BZ4qbKf81j44
FI=file-JB6g4104ZfjGbFyxY1yb52p5
JB=job-JB7Jk684kjB0V0FqyjYz47XP
AP=app-J8kvz9Q40ZP1v2Q7KV7fy1qG

cat > "$TMP/describe/$FI.json" <<J
{"id":"$FI","project":"$PJ","name":"sample_annotated.vcf.gz","class":"file"}
J
cat > "$TMP/describe/$JB.json" <<J
{"id":"$JB","project":"$PJ","name":"workbook-run","class":"job"}
J
# An app has NO project. This is the shape that exposed the tab-collapse bug.
cat > "$TMP/describe/$AP.json" <<J
{"id":"$AP","project":null,"name":"eggd_generate_variant_workbook","class":"app"}
J

U="$BIN/dxurl"

# --- ID normalisation: prefix lowercased, hash untouched ---
out=$($U --no-name "Project-J9yxvY04kjB0BZ4qbKf81j44" 2>/dev/null)
assert_contains "uppercase prefix accepted" "$out" "J9yxvY04kjB0BZ4qbKf81j44"
out=$($U --no-name "PROJECT-J9yxvY04kjB0BZ4qbKf81j44" 2>/dev/null)
assert_contains "all-caps prefix accepted" "$out" "projects/J9yxvY04kjB0BZ4qbKf81j44"
# a hash differing only in case must NOT be folded
out=$($U --no-name "project-j9YXVy04KJb0bz4QBkF81J44" 2>/dev/null)
assert_contains "hash case preserved" "$out" "j9YXVy04KJb0bz4QBkF81J44"

# --- local validation happens BEFORE any API call ---
: > "$DX_STUB_CALLS"
assert_rc "bad hash length exits 2" 2 "$U" file-abc123
assert_eq "validation made no dx call" "0" "$(dx_call_count)"
assert_rc "unknown class exits 2" 2 "$U" banana-J9yxvY04kjB0BZ4qbKf81j44
err=$($U file-abc123 2>&1 >/dev/null)
assert_contains "error names the real cause" "$err" "24 alphanumeric"
assert_rc "--no-validate bypasses" 0 "$U" --no-validate --no-name project-SHORT

# --- composite project-X:file-Y must not call the API at all ---
: > "$DX_STUB_CALLS"
out=$($U "$PJ:$FI" 2>/dev/null)
assert_contains "composite builds a file URL" "$out" "id.values=$FI"
assert_eq "composite made no dx call" "0" "$(dx_call_count)"

# --- the base URL itself, so a wrong host cannot slip through ---
out=$($U --no-name "$PJ" 2>/dev/null)
assert_contains "URL starts at the platform host" "$out" "https://platform.dnanexus.com/"
assert_eq "DXURL_BASE is honoured" \
  "https://example.test/panx/projects/J9yxvY04kjB0BZ4qbKf81j44/data" \
  "$(DXURL_BASE=https://example.test $U --no-name "$PJ" 2>/dev/null)"

# --- URL shapes per class ---
assert_contains "project URL" "$($U --no-name "$PJ" 2>/dev/null)" \
  "/panx/projects/J9yxvY04kjB0BZ4qbKf81j44/data"
assert_contains "job URL" "$($U "$JB" 2>/dev/null)" \
  "/panx/projects/J9yxvY04kjB0BZ4qbKf81j44/monitor/job/JB7Jk684kjB0V0FqyjYz47XP"
assert_contains "file URL" "$($U "$FI" 2>/dev/null)" "scope=project&id.values=$FI"

# --- REGRESSION: an object with an empty project must not shift fields ---
# The worker output was tab-separated and read with IFS=$'\t'; tab is IFS
# whitespace, so the empty .project collapsed and name became "app".
out=$($U "$AP" 2>/dev/null)
assert_contains "app URL uses the app NAME"   "$out" "/app/eggd_generate_variant_workbook"
assert_not_contains "app URL is not /app/app" "$out" "/app/app"
out=$($U --md "$AP" 2>/dev/null)
assert_contains "app --md label is the name" "$out" "[eggd_generate_variant_workbook]"
out=$($U --tsv "$AP" 2>/dev/null)
assert_eq "app --tsv name field intact" "eggd_generate_variant_workbook" "$(cut -f2 <<<"$out")"

# --- output formats ---
out=$($U --md "$FI" 2>/dev/null)
assert_eq "--md is [name](url)" "1" "$(grep -c '^\[sample_annotated.vcf.gz\](https://' <<<"$out")"
out=$($U --tsv "$FI" 2>/dev/null)
assert_eq "--tsv id field"   "$FI"                     "$(cut -f1 <<<"$out")"
assert_eq "--tsv name field" "sample_annotated.vcf.gz" "$(cut -f2 <<<"$out")"
out=$($U --json "$FI" 2>/dev/null)
assert_eq "--json name" "sample_annotated.vcf.gz" "$(jq -r .name <<<"$out")"
assert_eq "--json class" "file"                   "$(jq -r .class <<<"$out")"
out=$($U --md --label 'Custom Text' "$FI" 2>/dev/null)
assert_contains "--label overrides link text" "$out" "[Custom Text]"

# --- stdin, including several IDs on one line ---
out=$(printf '%s\n%s\n' "$PJ" "$JB" | $U 2>/dev/null)
assert_lines "two IDs from stdin" 2 "$out"
out=$(printf '%s %s\n' "$PJ" "$JB" | $U 2>/dev/null)
assert_lines "two IDs on ONE stdin line" 2 "$out"

# --- reverse ---
assert_eq "reverse job"     "$JB" "$($U -r "https://platform.dnanexus.com/panx/projects/X/monitor/job/JB7Jk684kjB0V0FqyjYz47XP" 2>/dev/null)"
assert_eq "reverse project" "project-ABC" "$($U -r "https://platform.dnanexus.com/panx/projects/ABC/data" 2>/dev/null)"
assert_eq "reverse file"    "$FI" "$($U -r "https://platform.dnanexus.com/panx/projects/X/data/?scope=project&id.values=$FI" 2>/dev/null)"
rt=$($U --no-name "$PJ" 2>/dev/null); assert_eq "reverse round-trips" "$PJ" "$($U -r "$rt" 2>/dev/null)"

# --- cache: second lookup must not call the API ---
isolate_cache "$TMP"; : > "$DX_STUB_CALLS"
$U --md "$FI" >/dev/null 2>&1
cold=$(dx_call_count)
: > "$DX_STUB_CALLS"
warm_out=$($U --md "$FI" 2>/dev/null)
assert_eq "cold lookup called dx" "1" "$cold"
assert_eq "warm lookup called dx 0 times" "0" "$(dx_call_count)"
assert_contains "warm output still correct" "$warm_out" "sample_annotated.vcf.gz"
: > "$DX_STUB_CALLS"; $U --refresh --md "$FI" >/dev/null 2>&1
assert_eq "--refresh re-queries" "1" "$(dx_call_count)"
: > "$DX_STUB_CALLS"; $U --no-cache --md "$FI" >/dev/null 2>&1
assert_eq "--no-cache re-queries" "1" "$(dx_call_count)"

# --- mixed valid/invalid: good URLs still emitted, exit 1 ---
out=$($U --no-name "$PJ" file-abc123 2>/dev/null); rc_mixed=$?
assert_contains "mixed run emits the good URL" "$out" "J9yxvY04kjB0BZ4qbKf81j44"
assert_eq "mixed run exits 1" "1" "$rc_mixed"

# --- notices must never pollute stdout (the old dx-url's bug) ---
out=$($U --no-name "$PJ" 2>/dev/null)
assert_lines "stdout is exactly one URL" 1 "$out"
assert_not_contains "no clipboard notice on stdout" "$out" "opied"

printf 'dxurl: %d passed, %d failed\n' "$PASS" "$FAIL"
((FAIL == 0))
