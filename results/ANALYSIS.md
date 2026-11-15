# CSE513 Assignment 2 — Simulator results, tests and analysis (Sections 2–4)

All numbers below come from `traces/*.csv` / `traces/*.txt` and `results/summary.csv`,
produced by `make traces`. All tests are reproduced by `make test` and `sh tests/mutation.sh`.

Cost model (fixed teaching assumptions): m = 1 µs per completed reference, Tin = 10,000 µs per
page input (every fault, including initial fills), Tout = 10,000 µs per dirty eviction.
Total = N·m + F·Tin + D·Tout; average = Total / N. These are model results, not Ubuntu measurements.

## 1. Summary of the six required runs

| Run | Policy | Frames | N | Hits | Faults (F) | Evictions | Dirty writebacks (D) | Resident dirty at end | Total (µs) | Avg/ref (µs) |
|---|---|---|---|---|---|---|---|---|---|---|
| A | FIFO  | 3 | 20 | 5  | 15 | 12 | 6 | 0 | 210,020 | 10,501.000 |
| A | LRU   | 3 | 20 | 8  | 12 | 9  | 4 | 1 (page 1) | 160,020 | 8,001.000 |
| A | OPT   | 3 | 20 | 11 | 9  | 6  | 3 | 1 (page 1) | 120,020 | 6,001.000 |
| A | CLOCK | 3 | 20 | 6  | 14 | 11 | 5 | 0 | 190,020 | 9,501.000 |
| B | FIFO  | 3 | 12 | 3  | 9  | 6  | 0 | 0 | 90,012  | 7,501.000 |
| B | FIFO  | 4 | 12 | 2  | 10 | 6  | 0 | 0 | 100,012 | 8,334.333 |

Example cost calculation (A, LRU): 20·1 + 12·10,000 + 4·10,000 = 160,020 µs; 160,020 / 20 = 8,001 µs.

The fault counts of Workload A (FIFO 15, LRU 12, OPT 9) match the lecture's page sequence,
which is expected because the operations do not influence victim selection; only the dirty
bits, writebacks and cost are new.

## 2. Hand traces vs machine traces

The hand traces (first eight steps of A under all four policies; all twelve steps of B with
3 and 4 frames) were calculated before running the code and transcribed into
`tests/expected/*.csv`. `sh tests/run_tests.sh` compares them row by row with the machine
trace (step, page, operation, hit/fault, victim, writeback, frame contents, dirty bits, and
for CLOCK the reference bits and next hand position).

Result: all six hand traces match the machine traces in every decision.

Discrepancies found while comparing were omissions in the first hand draft, not different
decisions: (1) the CLOCK hand position was not written for steps 1–4 and 8; (2) in B with
3 frames, the victim column was left blank at steps 10 and 11 although both are faults
(victims 1 and 2, the oldest insertions from steps 5 and 6); (3) the B tables did not show
dirty bits. Re-tracing those steps by hand gave hand = F1, F2, F0, F1 (steps 1–4) and F1
(step 8), and victims 1 and 2, which agree with the machine output. All B references are
reads, so every dirty bit stays 0 and D = 0.

## 3. Student test 1 — dirty-state test (FIFO, 2 frames)

Sequence: `1:R 1:W 1:R 2:R 3:R 1:R 1:W` (calculated by hand first, `tests/expected/T1_FIFO_2.csv`).

| Step | Ref | Result | Victim | Writeback | Frames after (page(D)) | What it shows |
|---|---|---|---|---|---|---|
| 1 | 1:R | FAULT | none | no  | 1(D0) -     | initial fill, loaded page starts clean |
| 2 | 1:W | HIT   | none | no  | 1(D1) -     | write hit sets dirty 0→1 |
| 3 | 1:R | HIT   | none | no  | 1(D1) -     | later read of same page keeps dirty = 1 |
| 4 | 2:R | FAULT | none | no  | 1(D1) 2(D0) | initial fill (not an eviction) |
| 5 | 3:R | FAULT | 1    | YES | 3(D0) 2(D0) | dirty eviction: one writeback before reuse |
| 6 | 1:R | FAULT | 2    | no  | 3(D0) 1(D0) | reload of page 1 starts clean; clean victim |
| 7 | 1:W | HIT   | none | no  | 3(D0) 1(D1) | dirty again; still resident at the end |

N = 7, hits = 3, faults = 4 (2 initial fills), evictions = 2, D = 1, final resident dirty = 1 (page 1, not flushed).
Total = 7·1 + 4·10,000 + 1·10,000 = 50,007 µs; average = 7,143.857 µs.

When the dirty bit is retained: from the first write until the page leaves its frame — read
hits (step 3) and further writes do not clear it. When it resets: only when the page is
(re)loaded into a frame (step 6), because the new copy is identical to the backing copy.
The writeback happens at eviction (step 5), never at the write itself, and dirty pages still
resident at the end are reported separately rather than flushed.

## 4. Student test 2 — cost comparison (2 frames)

Sequence: `1:R 1:W 2:R 1:R 3:R` (hand traces in `tests/expected/T2_LRU_2.csv`, `T2_OPT_2.csv`).
Steps 1–4 are identical for every policy: frames `1(D1) 2(D0)`. Step 5 (3:R) needs a victim:

| Policy | Step-5 victim and reason | Faults | D | Total (µs) | Avg (µs) |
|---|---|---|---|---|---|
| LRU   | page 2 (used at step 3, page 1 used at step 4) — clean | 3 | 0 | 30,005 | 6,001 |
| OPT   | page 1 — neither page is used again, tie → lowest frame index (frame 0) — dirty | 3 | 1 | 40,005 | 8,001 |
| FIFO  | page 1 (inserted first) — dirty | 3 | 1 | 40,005 | 8,001 |
| CLOCK | page 1 (both reference bits cleared, hand back at frame 0) — dirty | 3 | 1 | 40,005 | 8,001 |

LRU and OPT have the same fault count with the same sequence and capacity, yet OPT's modeled
time is 33% higher (40,005 vs 30,005 µs). Fault count alone misses this because a dirty
eviction costs a writeback (Tout = 10,000 µs) in addition to the page input, so the modeled
cost depends on F + D, not F. (LRU leaves page 1 dirty and resident; under the stated rules
that deferred writeback is reported but not charged.)

## 5. Verification

- After every step the simulator checks: no page is resident twice, residency never exceeds
  capacity, empty frames are never dirty, dirty/reference bits are 0/1, the CLOCK hand is in
  range. At the end it checks hits + faults = N, writebacks ≤ evictions ≤ faults, and
  evictions = faults − initial fills. Every run prints `verification=PASS`; a violation would
  stop the program with exit status 3.
- Differential testing: `tests/reference_sim.py` is an independent model written from the
  rules with different data structures (explicit FIFO queue, LRU recency list). On 2,000
  seeded random workloads (1–8 frames, up to 60 references, all four policies) every trace
  row and every counter is identical. On a mismatch the script prints the first differing step.
- Hand-vs-machine comparison (Section 2) and 15 input-validation tests (frames 0/65/"three",
  page 1000/−1/+7, missing page or operation, `7:X`, `7:r`, empty sequence, unknown policy,
  257 references; 256 references with 64 frames accepted). Total: 30 checks, 0 failures.
- Mutation check (`tests/mutation.sh`, output in `results/mutation_tests.txt`): five
  deliberate bugs were injected into copies of the simulator; all five were detected, each
  with the first differing decision reported:

| Mutation | Detected by | First differing decision |
|---|---|---|
| M1 reloaded page keeps old dirty bit | 8 checks | A FIFO step 6: dirty bits `1 1 0` instead of `1 0 0` |
| M2 a read clears the dirty bit | 10 checks | A FIFO step 5: 0:R hit cleared page 0's dirty bit |
| M3 LRU recency not updated on hits | 4 checks | A LRU step 6: victim 0 instead of 1 |
| M4 OPT tie-break → highest frame index | 3 checks (only test 2 + differential) | T2 OPT step 5: victim 2 instead of 1 |
| M5 writeback counted for clean victims | 13 checks | A FIFO step 4: writeback YES for clean page 7 |

## 6. Belady's anomaly in Workload B

FIFO with 3 frames takes 9 faults; with 4 frames it takes 10 — more memory, more faults.
The first divergence is at steps 5–6: with 4 frames, 1:R and 2:R are hits, but FIFO does not
refresh insertion age on a hit, so pages 1 and 2 remain the oldest. At step 7 (5:R) page 1 is
evicted, then each following fault evicts exactly the page needed next: steps 8–12 are five
consecutive faults (victims 2, 3, 4, 5, 1). With 3 frames, steps 5–6 faulted and re-inserted
1 and 2, which made them the youngest; after step 7 the frames hold {5, 1, 2} and steps 8–9
are hits. FIFO is not a stack algorithm: the set resident with 3 frames is not always a subset
of the set resident with 4 frames (after step 7: {5,1,2} vs {5,2,3,4}). LRU and OPT are stack
algorithms and cannot show the anomaly.

## 7. Does OPT necessarily have the lowest modeled time?

No. OPT minimises the number of faults in this model, but it ignores whether its victim is
dirty, and its tie-break is the lowest frame index, not the clean page. In Workload A OPT is
also the cheapest (120,020 µs) because it happens to have the fewest writebacks too (3). In
student test 2, OPT and LRU both fault 3 times, but OPT evicts dirty page 1 while LRU evicts
clean page 2, so OPT costs 40,005 µs and LRU 30,005 µs. With Tin = Tout the cost is
N + 10,000·(F + D), so a policy with equal (or slightly more) faults but fewer dirty
evictions can beat OPT. The mutation check also shows that OPT's tie-break rule — invisible
in Workload A — decides the writeback cost in test 2.

## 8. Bugs and rejected assumptions exposed by the tests

1. The supplied parser (`strtol`) silently accepted `+7` and ` 7` as page 7. Running the
   original: `./replacement FIFO 3 +7 " 7" 0` printed a valid trace with page 7 twice. The
   assignment requires rejecting invalid input with an explanation, so input is now parsed
   strictly (digits only); test "plus sign page" covers it.
2. The supplied program substituted the lecture sequence when no references were given. The
   assignment requires a nonempty sequence, so an empty sequence is now rejected.
3. Rejected assumption: "a write miss does not need a page input". The model has no zero-fill
   or whole-page-write optimisation, so every miss (read or write) is charged Tin; e.g. A FIFO
   step 7 (0:W miss) is a fault with one page input.
4. Rejected assumption: "FIFO, CLOCK and OPT behave alike so OPT's tie-break does not matter".
   Mutation M4 passes every Workload A/B check and is caught only by student test 2 (and the
   differential test), showing that tie-breaks determine writeback cost.

## 9. Model vs real Linux

This is the assignment's simplified model: one process, fixed frames, no background
writeback, no prefetch/fault-around, no sharing, fixed transfer costs, and no flush at the end.
Linux uses an approximate-LRU active/inactive list scheme, cleans dirty pages in the background
before reclaim, reads ahead, and its costs depend on the device and queueing. The results
above compare policies under the same assumptions; they do not predict Ubuntu performance.
