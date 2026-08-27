#!/usr/bin/env bash
set -uo pipefail
source "$REPO/tests/lib.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/describe"
use_dx_stub "$TMP"

PJ=project-J9yxvY04kjB0BZ4qbKf81j44
DONE=job-JB7Jk684kjB0V0FqyjYz47XP
FAILED=job-JB7Jk684kjB0V0FqyjYz47XQ
RUNNING=job-JB7Jk684kjB0V0FqyjYz47XR
BARE=job-JB7Jk684kjB0V0FqyjYz47XS

# 143s runtime, a real price
cat > "$TMP/describe/$DONE.json" <<J
{"id":"$DONE","name":"workbook-run","executableName":"eggd_generate_variant_workbook",
 "state":"done","project":"$PJ","folder":"/out","launchedBy":"user-rswilson1",
 "created":1787747481065,"startedRunning":1787747554000,"stoppedRunning":1787747697912,
 "instanceType":"mem1_ssd1_v2_x4","totalPrice":0.01108921911111111,
 "currency":{"code":"USD"},"rootExecution":"$DONE","parentJob":null,
 "output":{"xlsx_report":{"\$dnanexus_link":"file-x"}},"originalInput":{"vcf":"file-y"},
 "totalEgress":{"internetEgress":11968,"regionLocalEgress":0}}
J
cat > "$TMP/describe/$FAILED.json" <<J
{"id":"$FAILED","name":"broken-run","executableName":"swiss-army-knife",
 "state":"failed","project":"$PJ","startedRunning":1787747554000,
 "stoppedRunning":1787747574000,"totalPrice":0.002,"currency":{"code":"GBP"},
 "failureReason":"AppError","failureMessage":"bcftools exited with status 1"}
J
# still running: no stoppedRunning, no price yet - a known-weak area
cat > "$TMP/describe/$RUNNING.json" <<J
{"id":"$RUNNING","name":"in-flight","executableName":"eggd_vep","state":"running",
 "project":"$PJ","startedRunning":$(( ($(date +%s) - 90) * 1000 )),
 "totalPrice":null,"currency":{"code":"USD"}}
J
# minimal record: almost every field absent
cat > "$TMP/describe/$BARE.json" <<J
{"id":"$BARE","state":"idle","project":"$PJ"}
J
cat > "$TMP/find_jobs.json" <<J
[{"id":"$DONE","describe":$(cat "$TMP/describe/$DONE.json")},
 {"id":"$FAILED","describe":$(cat "$TMP/describe/$FAILED.json")}]
J
cat > "$TMP/find_jobs_failed.json" <<J
[{"id":"$FAILED","describe":$(cat "$TMP/describe/$FAILED.json")}]
J
cat > "$TMP/watch.log" <<'L'
2026-08-26 13:34:49 workbook STDOUT Total variants in input vcf: 664
2026-08-26 13:34:49 workbook STDOUT Total variants included: 70
2026-08-26 13:34:49 workbook STDOUT Total variants excluded: 594
2026-08-26 13:34:50 workbook STDOUT Writing workbook
2026-08-26 13:34:51 workbook STDERR warning: something noisy
L

J_="$BIN/dxjob"

# --- summary line: state, duration, cost ---
out=$($J_ "$DONE" 2>/dev/null)
assert_contains "state shown"                "$out" "done"
assert_contains "duration formatted (2m23s)" "$out" "2m23s"
assert_contains "cost with USD symbol"       "$out" '$0.0111'
assert_contains "executable name"            "$out" "eggd_generate_variant_workbook"

out=$($J_ "$FAILED" 2>/dev/null)
assert_contains "GBP symbol honoured" "$out" "£0.0020"
assert_rc "failed job exits 1" 1 "$J_" "$FAILED"
assert_rc "done job exits 0"   0 "$J_" "$DONE"

# --- detail block ---
out=$($J_ -l "$DONE" 2>/dev/null)
assert_contains "detail: instance"  "$out" "mem1_ssd1_v2_x4"
assert_contains "detail: launcher"  "$out" "user-rswilson1"
assert_contains "egress humanised"  "$out" "11.7KB"
assert_not_contains "no raw python dict" "$out" "internetEgress"
out=$($J_ -l "$FAILED" 2>/dev/null)
assert_contains "detail: failure reason"  "$out" "AppError"
assert_contains "detail: failure message" "$out" "bcftools exited with status 1"

# --- a running job must not crash on the absent stoppedRunning ---
out=$($J_ "$RUNNING" 2>/dev/null); rc=$?
assert_eq "running job exits 0" "0" "$rc"
assert_contains "running state shown" "$out" "running"
assert_contains "running cost shows -" "$out" "-"
out=$($J_ -l "$RUNNING" 2>/dev/null)
assert_contains "running detail has a runtime" "$out" "1m"

# --- a nearly-empty record must not crash ---
assert_rc "sparse record exits 0" 0 "$J_" "$BARE"
out=$($J_ "$BARE" 2>/dev/null)
assert_contains "sparse record shows its state" "$out" "idle"

# --- listings ---
out=$($J_ --recent 5 2>/dev/null)
assert_contains "listing includes job IDs" "$out" "$DONE"
assert_contains "listing shows failure inline" "$out" "AppError"
out=$($J_ --failed 2>/dev/null)
assert_contains     "--failed includes the failure" "$out" "$FAILED"
assert_not_contains "--failed excludes the done job" "$out" "$DONE"

# --- log filtering, the pattern this replaces ---
out=$($J_ --log "$DONE" --grep 'Total variants (in input|included|excluded)' 2>/dev/null)
assert_lines "grep keeps exactly 3 lines" 3 "$out"
assert_not_contains "grep drops unmatched" "$out" "Writing workbook"
out=$($J_ --log "$DONE" --tail 2 2>/dev/null)
assert_lines "--tail 2 keeps 2 lines" 2 "$out"
out=$($J_ --log "$DONE" 2>/dev/null)
assert_lines "unfiltered log is 5 lines" 5 "$out"
assert_rc "bad --grep regex exits 2" 2 "$J_" --log "$DONE" --grep '['

# --- io ---
assert_eq "--outputs" "file-x" "$($J_ --outputs "$DONE" 2>/dev/null | jq -r '.xlsx_report."$dnanexus_link"')"
assert_eq "--inputs"  "file-y" "$($J_ --inputs  "$DONE" 2>/dev/null | jq -r .vcf)"

printf 'dxjob: %d passed, %d failed\n' "$PASS" "$FAIL"
((FAIL == 0))
