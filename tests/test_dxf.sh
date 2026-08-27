#!/usr/bin/env bash
set -uo pipefail
source "$REPO/tests/lib.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/find_data"
use_dx_stub "$TMP"

PJ=project-J9yxvY04kjB0BZ4qbKf81j44
mk() {  # id name folder [size]
  printf '{"project":"%s","id":"%s","describe":{"id":"%s","project":"%s","class":"file","name":"%s","folder":"%s","state":"closed","size":%s,"modified":1787747701072}}' \
    "$PJ" "$1" "$1" "$PJ" "$2" "$3" "${4:-1024}"
}

# BAMs: sidecar-indexed, stem-indexed, orphan; plus a same-name file in
# another folder, to check pairing is folder-aware.
cat > "$TMP/find_data/STAR.bam.json" <<J
[$(mk file-b001 A_markdup.bam /runs/r1 5000),
 $(mk file-b002 B_markdup.bam /runs/r1),
 $(mk file-b003 C_markdup.bam /runs/r2),
 $(mk file-b004 A_markdup.bam /runs/r2)]
J
cat > "$TMP/find_data/STAR.bai.json" <<J
[$(mk file-i001 A_markdup.bam.bai /runs/r1),
 $(mk file-i002 B_markdup.bai /runs/r1)]
J
cat > "$TMP/find_data/STAR.vcf.gz.json" <<J
[$(mk file-v001 S1.vcf.gz /runs/r1), $(mk file-v002 S2.vcf.gz /runs/r1)]
J
cat > "$TMP/find_data/STAR.csi.json" <<J
[$(mk file-c001 S2.vcf.gz.csi /runs/r1)]
J
cat > "$TMP/find_data/default.json" <<J
[$(mk file-b001 A_markdup.bam /runs/r1 5000)]
J

F="$BIN/dxf"

# --- pairing, both index conventions ---
out=$($F --bam --pair 2>/dev/null)
assert_contains "sidecar .bam.bai paired"    "$out" "file-b001	file-i001"
assert_contains "stem .bai paired"           "$out" "file-b002	file-i002"
assert_contains "orphan reported as -"       "$out" "file-b003	-"
assert_contains "same name, other folder: -" "$out" "file-b004	-"

# --- .csi satisfies a bgzipped VCF where .tbi is absent ---
out=$($F --vcf --pair 2>/dev/null)
assert_contains "csi satisfies vcf.gz" "$out" "file-v002	file-c001"
assert_contains "vcf with no index"    "$out" "file-v001	-"

# --- --missing / --require-index ---
out=$($F --bam --pair --missing 2>/dev/null)
assert_contains     "--missing lists the orphan"   "$out" "file-b003"
assert_not_contains "--missing excludes the paired" "$out" "file-b001"
assert_rc "--require-index exits 1 when one is missing" 1 "$F" --bam --pair --require-index
assert_rc "--missing exits 1 when nothing is missing" 1 "$F" --vcf --pair --missing --sample nomatch

# --- a pattern alongside a class narrows client-side ---
out=$($F 'C_markdup' --bam 2>/dev/null)
assert_contains     "pattern+class keeps the match"  "$out" "file-b003"
assert_not_contains "pattern+class drops the others" "$out" "file-b001"

# --- --sample ---
out=$($F --bam --sample B_markdup 2>/dev/null)
assert_eq "--sample narrows to one" "file-b002" "$out"

# --- output formats ---
out=$($F --bam --tsv 2>/dev/null | head -1)
assert_eq "--tsv name field"   "A_markdup.bam" "$(cut -f2 <<<"$out")"
assert_eq "--tsv folder field" "/runs/r1"      "$(cut -f3 <<<"$out")"
out=$($F --bam --json 2>/dev/null | head -1)
assert_eq "--json id" "file-b001" "$(jq -r .id <<<"$out")"
out=$($F --bam --paths 2>/dev/null | head -1)
assert_eq "--paths form" "$PJ:/runs/r1/A_markdup.bam" "$out"
out=$($F --bam --names 2>/dev/null | sort | head -1)
assert_eq "--names form" "A_markdup.bam" "$out"

# --- count / sum / sort / limit ---
assert_eq "--count" "4" "$($F --bam -c 2>/dev/null)"
assert_eq "--limit"  "2" "$($F --bam --limit 2 2>/dev/null | grep -c .)"
out=$($F --bam --sort size -R 2>/dev/null | head -1)
assert_eq "--sort size -R puts the largest first" "file-b001" "$out"
assert_contains "--sum is human readable" "$($F --bam -s 2>/dev/null)" "KB"

# --- no match exits 1 ---
assert_rc "no match exits 1" 1 "$F" --bam --sample zzznope

printf 'dxf: %d passed, %d failed\n' "$PASS" "$FAIL"
((FAIL == 0))
