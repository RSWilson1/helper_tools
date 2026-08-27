#!/usr/bin/env bash
# bfind needs no dx stub - it works on real files, so build real trees.
set -uo pipefail
source "$REPO/tests/lib.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

mkdir -p runs/r1/fastq runs/r2 refs logs .hidden work/nf node_modules
# BAMs: sidecar-indexed, stem-indexed, and two orphans
: > runs/r1/A_markdup.bam; : > runs/r1/A_markdup.bam.bai      # sidecar
: > runs/r1/B_markdup.bam; : > runs/r1/B_markdup.bai           # stem
: > runs/r2/C_markdup.bam                                      # orphan
: > runs/r2/D.cram                                             # orphan
# VCFs: .tbi, .csi, and an orphan
: > runs/r1/A.vcf.gz; : > runs/r1/A.vcf.gz.tbi
: > runs/r2/B.vcf.gz; : > runs/r2/B.vcf.gz.csi
: > runs/r2/C.vcf.gz
# FASTQ: one complete pair, one orphan
: > runs/r1/fastq/S1_R1_001.fastq.gz; : > runs/r1/fastq/S1_R2_001.fastq.gz
: > runs/r2/S2_R1_001.fastq.gz
# refs
: > refs/g.fa; : > refs/g.fa.fai
: > refs/decoy.fa
# noise that must be pruned
: > .hidden/h.bam; : > work/nf/w.bam; : > node_modules/n.bam
# sizes and a filename containing spaces
truncate -s 2G runs/r1/big.bam; : > runs/r1/big.bam.bai
: > "runs/r1/has space.bam"
printf 'ERROR\n' > logs/a.log; : > logs/empty.log

B="$BIN/bfind"

out=$($B --bam 2>/dev/null | sort)
assert_not_contains "prunes .hidden"      "$out" ".hidden"
assert_not_contains "prunes work/"        "$out" "work/nf"
assert_not_contains "prunes node_modules" "$out" "node_modules"

out=$($B --bam --orphan-index 2>/dev/null | sort)
assert_contains     "orphan: C_markdup.bam"        "$out" "C_markdup.bam"
assert_contains     "orphan: D.cram"               "$out" "D.cram"
assert_not_contains "sidecar .bam.bai not orphan"  "$out" "A_markdup.bam"
assert_not_contains "stem .bai not orphan"         "$out" "B_markdup.bam"
assert_not_contains "big.bam is indexed"           "$out" "big.bam"

out=$($B --vcf --orphan-index 2>/dev/null | sort)
assert_contains     "orphan vcf: C.vcf.gz" "$out" "C.vcf.gz"
assert_not_contains ".tbi satisfies vcf.gz" "$out" "A.vcf.gz"
assert_not_contains ".csi satisfies vcf.gz" "$out" "B.vcf.gz"

out=$($B --ref --orphan-index 2>/dev/null | sort)
assert_contains     "orphan fasta: decoy.fa" "$out" "decoy.fa"
assert_not_contains ".fai satisfies fasta"   "$out" "g.fa"

out=$($B --fastq --paired 2>/dev/null)
assert_contains     "unpaired R1 found"   "$out" "S2_R1_001.fastq.gz"
assert_not_contains "complete pair kept out" "$out" "S1_R1"

out=$($B --log --empty 2>/dev/null)
assert_contains     "--empty finds empty.log" "$out" "empty.log"
assert_not_contains "--empty skips a.log"     "$out" "a.log"

out=$($B --bam --sample C_markdup 2>/dev/null)
assert_contains "--sample matches"  "$out" "C_markdup.bam"
assert_lines    "--sample is exact" 1 "$out"

out=$($B --bam --sort -size --head 1 2>/dev/null)
assert_contains "--sort -size puts big.bam first" "$out" "big.bam"
out=$($B --bam --bigger-than 1G 2>/dev/null)
assert_contains "--bigger-than 1G finds big.bam" "$out" "big.bam"
assert_lines    "--bigger-than 1G finds only it" 1 "$out"

assert_eq "--count counts" "$($B --vcf 2>/dev/null | grep -c .)" "$($B --vcf -c 2>/dev/null)"

# filenames containing spaces: a known-weak area worth pinning down
out=$($B 'has space' 2>/dev/null)
assert_contains "pattern matches a name with a space" "$out" "has space.bam"
# 6 = A, B, C_markdup.bam, D.cram, big.bam, "has space.bam" (pruned ones excluded).
# If a space split one entry into two the count would read 7.
n=$($B --bam -c 2>/dev/null)
assert_eq "space-name counted once, not split" "6" "$n"

# --dry-run must not touch the filesystem, just print the command
out=$($B --vcf --dry-run 2>/dev/null)
assert_contains "--dry-run prints find" "$out" "find"
assert_contains "--dry-run shows -print0" "$out" "print0"

# no matches is exit 1, grep-style
assert_rc "no match exits 1" 1 "$B" --bam --sample zzzznope

printf 'bfind: %d passed, %d failed\n' "$PASS" "$FAIL"
((FAIL == 0))
