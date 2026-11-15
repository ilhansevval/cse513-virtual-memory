# Section 5 — Predictions (written BEFORE running on Ubuntu)

Recorded before any Ubuntu run. They are reasoned from how Linux handles anonymous private
memory; they are not copied from the lecture's macOS counts, and no exact number is promised.

## first-touch (16 MiB private anonymous mapping, one access per page)

With 4 KiB pages, 16 MiB = 4,096 pages. The program measures minor/major fault deltas with
`getrusage` around four phases.

| Phase | Prediction | Reason |
|---|---|---|
| mapping only (`mmap`) | ~0 minor, 0 major | `mmap` only creates a virtual memory area; no page-table entries or frames are set up until a page is touched (demand paging). |
| first read | up to ~4,096 minor, 0 major (could be far fewer) | Each untouched page faults on first access. For an anonymous page that is only read, Linux maps the shared read-only **zero page** instead of allocating a frame. If transparent huge pages (THP) are used for this area, one fault can cover 2 MiB (huge zero page) and the count drops to about 8. |
| first write | ~4,096 minor, 0 major (or ~8 with THP) | Writing a page that maps the zero page is a write to a read-only mapping: the kernel allocates a private zeroed frame (copy-on-write from the zero page) and updates the PTE. Expect roughly one fault per page, not zero, because the first read did not allocate frames. |
| repeat write | ~0 minor, 0 major | Pages are now private, present and writable; no fault is needed. |

Major faults: 0 in every phase, because anonymous memory has no file to read and the run is
far too small to cause swapping. Small extra minor faults may come from the C library and
`printf`/`getrusage` themselves (counters include runtime noise). Things that can change the
counts: page size (`getconf PAGESIZE`; a 16 KiB or 64 KiB page would mean 1,024 or 256 pages),
the THP setting (`/sys/kernel/mm/transparent_hugepage/enabled`: `always` vs `madvise`), the
zero-page handling, and other activity in the process.

## cow-observe (fork after writing 7, child writes 9)

Prediction for every run: `child_private_value=9 parent_private_value=7`, exit status 0.

Reason: the page is `MAP_PRIVATE`. After `fork`, parent and child share the frame and both
PTEs are made read-only for copy-on-write. When the child writes 9, it takes a COW fault and
the kernel gives the child its own copy, so the parent still sees 7. The printed values can
show isolation but cannot prove which physical frames were used, whether the copy happened
exactly at the child's write, or which process received the new frame.
