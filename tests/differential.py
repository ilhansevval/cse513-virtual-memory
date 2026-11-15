#!/usr/bin/env python3
"""Differential test: compare every CSV trace row of the C simulator with the independent
Python reference on many seeded random workloads. Reports the FIRST differing decision.
Usage: python3 tests/differential.py [path/to/replacement] [cases]"""
import os, random, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from reference_sim import simulate

binary = sys.argv[1] if len(sys.argv) > 1 else "./replacement"
cases = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
rng = random.Random(513)
checked = 0
for case in range(cases):
    policy = rng.choice(["FIFO", "LRU", "OPT", "CLOCK"])
    cap = rng.randint(1, 8)
    n = rng.randint(1, 60)
    pages = rng.randint(1, 12)
    refs = [(rng.randint(0, pages - 1), rng.choice("RW")) for _ in range(n)]
    tokens = ["%d:%s" % r for r in refs]
    out = subprocess.run([binary, "--csv", policy, str(cap)] + tokens,
                         capture_output=True, text=True)
    if out.returncode != 0:
        print("FAIL case %d: exit %d %s" % (case, out.returncode, out.stderr.strip()))
        sys.exit(1)
    c_rows = [l for l in out.stdout.splitlines()[1:] if not l.startswith("#")]
    py_rows, stats = simulate(policy, cap, refs)
    for i, (a, b) in enumerate(zip(c_rows, py_rows)):
        if a != b:
            print("FAIL case %d %s frames=%d refs=%s" % (case, policy, cap, " ".join(tokens)))
            print("  first differing step %d\n  C : %s\n  PY: %s" % (i + 1, a, b))
            sys.exit(1)
    if len(c_rows) != len(py_rows):
        print("FAIL case %d: row count differs" % case); sys.exit(1)
    summ = [l for l in out.stdout.splitlines() if l.startswith("# policy=")][0]
    for key in ("hits", "faults", "evictions"):
        if " %s=%d " % (key, stats[key]) not in summ + " ":
            print("FAIL case %d summary %s: %s" % (case, key, summ)); sys.exit(1)
    if "dirty_writebacks=%d " % stats["writebacks"] not in summ:
        print("FAIL case %d writebacks: %s" % (case, summ)); sys.exit(1)
    checked += 1
print("PASS differential: %d random workloads, all trace rows and counters identical" % checked)
