#!/bin/sh
# Produce the six required runs (+ the two student tests) as CSV and text traces,
# and a summary table (results/summary.csv, results/summary.md). Run from project root.
set -e
BIN=./replacement
mkdir -p traces results
run() { # tag policy frames workload
    $BIN --csv  --file "$4" "$2" "$3" > "traces/$1.csv"
    $BIN        --file "$4" "$2" "$3" > "traces/$1.txt"
}
run A_FIFO_3   FIFO  3 workloads/workload_A.txt
run A_LRU_3    LRU   3 workloads/workload_A.txt
run A_OPT_3    OPT   3 workloads/workload_A.txt
run A_CLOCK_3  CLOCK 3 workloads/workload_A.txt
run B_FIFO_3   FIFO  3 workloads/workload_B.txt
run B_FIFO_4   FIFO  4 workloads/workload_B.txt
run T1_dirty_FIFO_2 FIFO 2 workloads/test1_dirty_state.txt
for p in FIFO LRU OPT CLOCK; do run "T2_cost_${p}_2" "$p" 2 workloads/test2_cost_comparison.txt; done

field() { echo "$2" | tr ' ' '\n' | grep "^$1=" | head -1 | cut -d= -f2; }
echo "run,policy,frames,references,hits,faults,initial_fills,evictions,dirty_writebacks,final_resident_dirty,total_time_us,avg_time_us" > results/summary.csv
{
echo "| Run | Policy | Frames | N | Hits | Faults | Evictions | Dirty writebacks | Resident dirty at end | Total time (us) | Avg time/ref (us) |"
echo "|---|---|---|---|---|---|---|---|---|---|---|"
} > results/summary.md
for f in traces/*.csv; do
    tag=$(basename "$f" .csv)
    s=$(grep '^# policy=' "$f" | sed 's/^# //'); c=$(grep '^# total_time_us=' "$f" | sed 's/^# //')
    pol=$(field policy "$s"); fr=$(field frames "$s"); n=$(field references "$s"); h=$(field hits "$s")
    fa=$(field faults "$s"); fi_=$(field initial_fills "$s"); ev=$(field evictions "$s")
    wb=$(field dirty_writebacks "$s"); rd=$(field final_resident_dirty "$s")
    tot=$(field total_time_us "$c"); avg=$(field avg_time_us "$c")
    echo "$tag,$pol,$fr,$n,$h,$fa,$fi_,$ev,$wb,$rd,$tot,$avg" >> results/summary.csv
    echo "| $tag | $pol | $fr | $n | $h | $fa | $ev | $wb | $rd | $tot | $avg |" >> results/summary.md
done
cat results/summary.md
