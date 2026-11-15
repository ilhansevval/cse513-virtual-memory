# CSE513 Assignment 2 — Virtual Memory: Predict, Simulate, and Observe

Locally runnable page-replacement simulator (FIFO, LRU, OPT, CLOCK) extended with
read/write operations, dirty pages, writeback cost accounting and verification, plus the
scripts and logs for the Ubuntu observations. No paid services or network access needed.

## Dependencies

- A C11 compiler (`cc`/`gcc`/`clang`) and `make` — required for the simulator.
- POSIX `sh` with `awk`, `cmp`, `paste`, `grep` — for the test and trace scripts.
- Python 3 (standard library only) — only for the differential and mutation tests.
- Ubuntu (physical, VM, WSL or container) with `bash` and a C compiler — for Section 5.

## Build and run

```sh
make                     # builds ./replacement  (cc -std=c11 -O2 -Wall -Wextra -Wpedantic)
make traces              # regenerates traces/*.csv, traces/*.txt and results/summary.{csv,md}
make test                # 30 checks: hand traces, summaries, invalid input, differential test
sh tests/mutation.sh     # injects 5 deliberate bugs and shows the tests catch each one
```

Single runs:

```sh
./replacement LRU 3 "7:R 0:W 1:R 2:W 0:R 3:R 0:W 4:R 2:R 3:W 0:R 3:R 2:W 1:R 2:R 0:R 1:W 7:R 0:R 1:R"
./replacement --csv --file workloads/workload_A.txt OPT 3
./replacement --quiet --file workloads/workload_B.txt FIFO 4
```

Usage: `./replacement [--csv] [--quiet] [--file PATH] FIFO|LRU|OPT|CLOCK FRAMES [REFS ...]`

| Option | Meaning |
|---|---|
| `--csv` | CSV trace; summary lines follow, prefixed with `# ` |
| `--quiet` | summary only |
| `--file PATH` | read references from a file (whitespace separated, `#` starts a comment) |

Exit status: 0 success, 2 invalid input (with an explanation on stderr), 3 internal
verification failure.

## Input format

- `FRAMES`: decimal integer 1–64.
- References: 1–256 tokens `page:op`, page a decimal integer 0–999 (digits only — no sign,
  spaces or hex), op exactly `R` or `W`. Example: `7:R 0:W`. Tokens may be separate
  arguments or one quoted argument; `--file` and arguments can be combined.

## Output

Per reference: step, page and operation, HIT/FAULT, victim (or none), whether a dirty
writeback occurred, and every frame's page and dirty bit after the access; for CLOCK also
reference bits and the next hand position. CSV columns:
`step,page,op,result,victim,dirty_writeback,frames,dirty_bits,ref_bits,next_hand`.
Summary: references, hits, faults, initial fills, evictions, dirty writebacks, resident
dirty pages at the end (listed, not flushed), total and average modeled time
(m = 1 µs, Tin = Tout = 10,000 µs), and the verification result.

## Model rules implemented

One process, initially empty frames; every miss is a fault with one page input (initial
fills are not evictions); a loaded page starts clean, W sets dirty, R leaves it unchanged;
a dirty victim costs one writeback; no flush at the end. FIFO/LRU/OPT use the lowest-index
empty frame first; FIFO ignores hits; LRU updates on reads and writes; OPT evicts the page
used farthest in the future (never-used = farthest, ties → lowest frame index); CLOCK starts
at hand 0, clears reference bits while advancing, installs at the first empty or R=0 frame,
sets R=1, advances once; a hit sets R=1 without moving the hand; dirty bits never affect
victim choice.

## Files

| Path | Description |
|---|---|
| `supplied/replacement.c` | Course-supplied starter, **unchanged** (reference only) |
| `supplied/first-touch.c`, `supplied/cow-observe.c` | Course-supplied observation programs, **unchanged** |
| `src/replacement.c` | Extended simulator. Policy victim logic reused from the supplied file and marked `[SUPPLIED]`; all additions marked `[A2]` |
| `Makefile` | build, traces, test targets |
| `workloads/` | Workload A, Workload B and the two student test workloads |
| `scripts/run_required.sh` | runs the 6 required runs + student tests, writes traces and summary |
| `traces/` | complete machine traces (`.csv` and readable `.txt`) for every run |
| `results/summary.csv`, `results/summary.md` | summary table of all runs |
| `results/ANALYSIS.md` | hand-vs-machine comparison, student tests, verification, Belady, OPT cost, bugs found |
| `results/mutation_tests.txt` | output of `tests/mutation.sh` |
| `tests/run_tests.sh` | test suite (hand traces, summaries, invalid input, differential) |
| `tests/expected/` | hand-calculated expected traces (calculated before running the code) |
| `tests/reference_sim.py` | independent Python reference model used for differential testing |
| `tests/differential.py` | compares C and Python traces on 2,000 seeded random workloads |
| `tests/mutation.sh` | mutation check (5 injected bugs) |
| `ubuntu/predictions.md` | Section 5 predictions, recorded before running |
| `ubuntu/run_ubuntu_experiments.sh` | records environment, compiles supplied programs, runs each 3× |
| `ubuntu/paste_in_terminal.sh` | self-contained version of the above (recreates the supplied files byte-for-byte), for pasting into a browser terminal |
| `ubuntu/logs/20261114_133737_killercoda/` | raw Ubuntu output (`all_output.log`, unedited) and per-run extracts |
| `ubuntu/OBSERVATIONS.md` | environment, prediction vs observation, interpretation |
| `report_src/` | LaTeX source of the PDF report (`pdflatex report.tex`; tables in `gen/` generated from `traces/` by `gen/tables.py`; scanned hand calculations in `scans/`) |

Supplied file checksums (sha256): `replacement.c` 9b0a6a43…a6, `first-touch.c` 8654b3dc…d8,
`cow-observe.c` 6b644254…e7.

## Known limitations

- Costs (m, Tin, Tout) are compile-time constants matching the assignment; change them in
  `src/replacement.c` if needed.
- OPT looks ahead with a simple O(N × frames) scan per fault — fine for ≤ 256 references.
- The text table is aligned for page numbers up to 3 digits; use `--csv` for tooling.
- Summary lines in `--csv` mode are `#` comments after the rows; CSV readers should skip them.
- References are taken from arguments or a file, not from standard input.
- The model is deliberately simplified (no background writeback, prefetch, sharing or end
  flush) and does not predict Linux performance.
- The differential/mutation tests need Python 3 and a writable temporary directory.
