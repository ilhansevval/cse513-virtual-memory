# Section 5 — Ubuntu observations and interpretation

Raw output (unedited): `ubuntu/logs/20261114_133737_killercoda/all_output.log`; per-run
extracts `first-touch_run{1,2,3}.txt`, `cow-observe_run{1,2,3}.txt` were cut from that file
without changes. (The final status line of the log was cut off when it was copied out of the
browser terminal: "…or the whole fol". No measurement line is affected.)

## Environment

| Item | Value |
|---|---|
| Environment type | Browser-based Ubuntu playground (Killercoda), a **KVM virtual machine** (`systemd-detect-virt` → `kvm`), accessed from a Mac |
| Release | Ubuntu 24.04.5 LTS (Noble Numbat) |
| Kernel | 6.8.0-147-generic, x86_64 |
| Page size | 4096 bytes |
| Compiler | cc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0 |
| CPUs / memory | 1 vCPU, 1.9 GiB RAM, 1.0 GiB swap (0 B used) |
| Transparent huge pages | `always [madvise] never` (madvise), `use_zero_page` = 1 — read only, not changed |
| Supplied files | sha256 identical to the course files (first-touch.c 8654b3dc…, cow-observe.c 6b644254…); 16 MiB bound unchanged |

Both programs compiled with the exact assignment commands (exit status 0). GCC printed
three `-Wmisleading-indentation` warnings for first-touch.c lines 19–21: each line has a `for`
loop followed by `struct rusage x=snapshot();` on the same line, which only *looks* like part
of the loop. It is not: the snapshot runs once after the loop, as intended. The warning is
about layout, not behaviour, so the supplied file was left unchanged.

## first-touch — prediction vs observation (three fresh processes)

| Phase | Prediction (recorded before running) | Run 1 | Run 2 | Run 3 | Match? |
|---|---|---|---|---|---|
| mapping only | ~0 minor, 0 major | 0 / 0 | 0 / 0 | 0 / 0 | yes |
| first read | up to ~4,096 minor (≈8 if THP), 0 major | 4096 / 0 | 4096 / 0 | 4096 / 0 | yes (4 KiB case) |
| first write | ~4,096 minor (≈8 if THP), 0 major | 4096 / 0 | 4096 / 0 | 4096 / 0 | yes (4 KiB case) |
| repeat write | ~0 minor, 0 major | 0 / 0 | 0 / 0 | 0 / 0 | yes |

(values are minor_delta / major_delta). Every run also printed `checksum=0 first_byte=2`.

Interpretation:

- **Mapping only = 0.** `mmap` created the virtual area only; no frame or page-table entry
  exists until a page is touched (demand paging).
- **First read = 4,096 = 16 MiB / 4 KiB.** Exactly one minor fault per page touched. Each
  read fault on untouched anonymous memory was satisfied by mapping the shared, read-only
  zero page — `checksum=0` confirms every byte read was zero. No disk was involved, so the
  faults are minor. THP is `madvise` and the program does not call `madvise`, so 4 KiB pages
  were used; with THP `always` (and the huge zero page) the count could have been about 8.
- **First write = 4,096 again**, not 0. Reading did not give the process private frames:
  each PTE pointed to the read-only zero page, so the first write to every page faulted and
  the kernel allocated a private zero-filled frame (copy-on-write from the zero page).
  `first_byte=2` confirms both writes (=1, then +=1) reached the private page.
- **Repeat write = 0.** The pages were now present, private and writable.
- **Major faults = 0 everywhere**: anonymous memory has no file to read and nothing was
  swapped (swap used 0 B; 16 MiB is small next to 1.5 GiB available).
- The three runs are identical. `getrusage(RUSAGE_SELF)` counts only this process, and the
  snapshots surround the loops, so library start-up and `printf` faults fall outside the
  measured intervals; other processes on the VM do not affect these counters. The result
  should not be generalised as "one fault per 4 KiB": a different page size, THP `always`,
  disabled zero-page use, or a different kernel could change the counts.

## cow-observe — prediction vs observation

Prediction: `child_private_value=9 parent_private_value=7`, exit 0.
Observed in all three fresh processes: `child_private_value=9 parent_private_value=7`, exit 0.
Prediction and observation agree.

How the private writes stay isolated: the parent writes 7 into a `MAP_PRIVATE` anonymous
page, then forks. The child gets a copy of the page tables pointing at the same frame, and
both mappings are made read-only for copy-on-write. When the child writes 9, the write
faults; the kernel gives the child a private copy of the page and repoints the child's PTE
to it with write permission. The parent's mapping still refers to the page containing 7,
so the parent reads 7 after the child has exited.

What the printed values cannot prove: which physical frames were used (no frame numbers
are printed), that the two processes ever shared a frame, exactly when the copy was made
(at the child's write, or earlier), or which process received the new frame. They only show
that each process sees its own private value.

## Model vs observation

The simulator (Sections 2–4) is a simplified replacement model with fixed transfer costs;
these Ubuntu counts are measurements of real demand paging and COW in one environment.
Neither is used to predict the other's numbers.
