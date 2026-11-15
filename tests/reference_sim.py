#!/usr/bin/env python3
"""Independent reference model for differential testing (written from the assignment rules,
not translated from the C code). Uses different data structures on purpose:
FIFO = explicit insertion queue, LRU = recency list, OPT = look-ahead per candidate,
CLOCK = list of [page, dirty, ref] slots with a hand index.

Prints the same CSV trace format as `replacement --csv` (rows only, no summary) and,
with --summary, a single summary line.
"""
import sys

def simulate(policy, cap, refs):
    frames = [None] * cap          # page or None
    dirty = [0] * cap
    refbit = [0] * cap
    fifo_queue = []                # frame indices in insertion order
    recency = []                   # frame indices, least recent first
    hand = 0
    rows = []
    stats = dict(hits=0, faults=0, evictions=0, writebacks=0)
    for t, (page, op) in enumerate(refs):
        victim, wb = None, False
        if page in frames:
            idx = frames.index(page)
            stats["hits"] += 1
            result = "HIT"
        else:
            stats["faults"] += 1
            result = "FAULT"
            if policy == "CLOCK":
                while frames[hand] is not None and refbit[hand] == 1:
                    refbit[hand] = 0
                    hand = (hand + 1) % cap
                idx = hand
                hand = (hand + 1) % cap
            elif None in frames:
                idx = frames.index(None)               # lowest-index empty frame
            elif policy == "FIFO":
                idx = fifo_queue[0]
            elif policy == "LRU":
                idx = recency[0]
            elif policy == "OPT":
                def next_use(i):
                    future = [p for p, _ in refs[t + 1:]]
                    return future.index(frames[i]) if frames[i] in future else float("inf")
                best = max(next_use(i) for i in range(cap))
                idx = min(i for i in range(cap) if next_use(i) == best)
            else:
                raise ValueError(policy)
            if frames[idx] is not None:
                victim = frames[idx]
                stats["evictions"] += 1
                if dirty[idx]:
                    wb = True
                    stats["writebacks"] += 1
            frames[idx] = page
            dirty[idx] = 0
            if idx in fifo_queue:
                fifo_queue.remove(idx)
            fifo_queue.append(idx)
        if idx in recency:
            recency.remove(idx)
        recency.append(idx)
        refbit[idx] = 1
        if op == "W":
            dirty[idx] = 1
        fr = " ".join("-" if p is None else str(p) for p in frames)
        db = " ".join("-" if frames[i] is None else str(dirty[i]) for i in range(cap))
        if policy == "CLOCK":
            tail = '"%s",%d' % (" ".join(str(b) for b in refbit), hand)
        else:
            tail = "-,-"
        rows.append('%d,%d,%s,%s,%s,%s,"%s","%s",%s' % (
            t + 1, page, op, result, "-" if victim is None else victim,
            "YES" if wb else "NO", fr, db, tail))
    resident_dirty = sum(1 for i in range(cap) if frames[i] is not None and dirty[i])
    n = len(refs)
    total = n * 1 + stats["faults"] * 10000 + stats["writebacks"] * 10000
    stats.update(references=n, final_resident_dirty=resident_dirty, total_time_us=total)
    return rows, stats

def parse(tokens):
    out = []
    for tok in tokens:
        p, o = tok.split(":")
        out.append((int(p), o))
    return out

if __name__ == "__main__":
    args = sys.argv[1:]
    summary = False
    if args and args[0] == "--summary":
        summary, args = True, args[1:]
    policy, cap = args[0], int(args[1])
    refs = parse(" ".join(args[2:]).split())
    rows, stats = simulate(policy, cap, refs)
    if summary:
        print(" ".join("%s=%s" % kv for kv in sorted(stats.items())))
    else:
        print("step,page,op,result,victim,dirty_writeback,frames,dirty_bits,ref_bits,next_hand")
        print("\n".join(rows))
