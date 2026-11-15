#!/bin/sh
# Test suite for the extended simulator. Run from the project root: sh tests/run_tests.sh
# 1) machine trace vs hand-calculated expected trace (reports the first differing step)
# 2) summary counters and costs of the student tests
# 3) invalid input is rejected with an explanation (exit status 2)
# 4) differential test against the independent Python reference model
BIN=./replacement
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS  $1"; }
bad() { fail=$((fail+1)); echo "FAIL  $1"; }

compare() { # name policy frames workload expected_csv
    name=$1; pol=$2; fr=$3; wl=$4; exp=$5
    rows=$(($(wc -l < "$exp") - 1))
    $BIN --csv --file "$wl" "$pol" "$fr" | grep -v '^#' | head -n $((rows + 1)) > /tmp/got.csv
    if cmp -s /tmp/got.csv "$exp"; then ok "$name (hand trace == machine trace, $rows steps)"
    else
        bad "$name"
        paste -d'\n' "$exp" /tmp/got.csv | awk 'NR%2==1{e=$0;next}{if(e!=$0){print "      first differing row:\n      hand   : " e "\n      machine: " $0; exit}}'
    fi
}
expect_summary() { # name policy frames workload pattern...
    name=$1; pol=$2; fr=$3; wl=$4; shift 4
    out=$($BIN --quiet --file "$wl" "$pol" "$fr")
    for pat in "$@"; do
        echo "$out" | grep -q -- "$pat" || { bad "$name: missing '$pat'"; echo "$out" | sed 's/^/      /'; return; }
    done
    ok "$name ($*)"
}
reject() { # name expected_message args...
    name=$1; msg=$2; shift 2
    err=$($BIN "$@" 2>&1 >/dev/null); st=$?
    if [ $st -eq 2 ] && echo "$err" | grep -q -- "$msg"; then ok "reject: $name -> $(echo "$err" | head -1)"
    else bad "reject: $name (status $st, stderr: $err)"; fi
}

echo "== 1. hand traces vs machine traces =="
compare "A FIFO 3 frames, first 8"  FIFO  3 workloads/workload_A.txt tests/expected/A_FIFO_3_first8.csv
compare "A LRU 3 frames, first 8"   LRU   3 workloads/workload_A.txt tests/expected/A_LRU_3_first8.csv
compare "A OPT 3 frames, first 8"   OPT   3 workloads/workload_A.txt tests/expected/A_OPT_3_first8.csv
compare "A CLOCK 3 frames, first 8" CLOCK 3 workloads/workload_A.txt tests/expected/A_CLOCK_3_first8.csv
compare "B FIFO 3 frames, all 12"   FIFO  3 workloads/workload_B.txt tests/expected/B_FIFO_3.csv
compare "B FIFO 4 frames, all 12"   FIFO  4 workloads/workload_B.txt tests/expected/B_FIFO_4.csv
compare "T1 dirty-state FIFO 2"     FIFO  2 workloads/test1_dirty_state.txt tests/expected/T1_FIFO_2.csv
compare "T2 cost LRU 2"             LRU   2 workloads/test2_cost_comparison.txt tests/expected/T2_LRU_2.csv
compare "T2 cost OPT 2"             OPT   2 workloads/test2_cost_comparison.txt tests/expected/T2_OPT_2.csv

echo "== 2. summaries and costs =="
expect_summary "T1 FIFO 2" FIFO 2 workloads/test1_dirty_state.txt "hits=3 " "faults=4 " "evictions=2 " "dirty_writebacks=1 " "final_resident_dirty=1" "pages=\[1\]" "total_time_us=50007 " "avg_time_us=7143.857"
expect_summary "T2 LRU 2"  LRU  2 workloads/test2_cost_comparison.txt "faults=3 " "dirty_writebacks=0 " "total_time_us=30005 "
expect_summary "T2 OPT 2"  OPT  2 workloads/test2_cost_comparison.txt "faults=3 " "dirty_writebacks=1 " "total_time_us=40005 "
expect_summary "B FIFO 3"  FIFO 3 workloads/workload_B.txt "faults=9 " "total_time_us=90012 "
expect_summary "B FIFO 4 (Belady)" FIFO 4 workloads/workload_B.txt "faults=10 " "total_time_us=100012 "
expect_summary "1 frame, all faults" LRU 1 workloads/workload_B.txt "hits=0 " "faults=12 " "evictions=11 "

echo "== 3. invalid input rejected with explanation =="
reject "frames 0"            "between 1 and 64"        FIFO 0 1:R
reject "frames 65"           "between 1 and 64"        FIFO 65 1:R
reject "frames not a number" "digits only"             FIFO three 1:R
reject "page 1000"           "between 0 and 999"       FIFO 3 1000:R
reject "negative page"       "digits only"             FIFO 3 -1:R
reject "plus sign page"      "digits only"             FIFO 3 +7:R
reject "missing operation"   "page:op"                 FIFO 3 7
reject "bad operation"       "R (read) or W (write)"   FIFO 3 7:X
reject "lower-case op"       "R (read) or W (write)"   FIFO 3 7:r
reject "missing page"        "page number is missing"  FIFO 3 :R
reject "empty sequence"      "sequence is empty"       FIFO 3
reject "unknown policy"      "must be FIFO, LRU"       RANDOM 3 1:R
too_many=$(i=0; while [ $i -lt 257 ]; do printf '1:R '; i=$((i+1)); done)
reject "257 references"      "at most 256"             FIFO 3 "$too_many"
exactly=$(i=0; while [ $i -lt 256 ]; do printf '%d:W ' $((i % 70)); i=$((i+1)); done)
if $BIN --quiet CLOCK 64 "$exactly" >/dev/null; then ok "accept: 256 references, 64 frames"; else bad "accept 256/64"; fi

echo "== 4. differential test against independent reference =="
if python3 -I tests/differential.py $BIN 2000; then pass=$((pass+1)); else fail=$((fail+1)); fi

echo "== result: $pass passed, $fail failed =="
[ $fail -eq 0 ]
