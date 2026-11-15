#!/bin/sh
# Mutation check: inject deliberate bugs into copies of the simulator and confirm the
# test suite detects each one (reports the first differing decision). Run from project root.
set -u
TMP=${TMPDIR:-/tmp}/a2_mutation; mkdir -p "$TMP"
mutate() { # id description sed-expression
    id=$1; desc=$2; expr=$3
    sed "$expr" src/replacement.c > "$TMP/$id.c"
    if cmp -s src/replacement.c "$TMP/$id.c"; then echo "[$id] mutation did not apply"; return; fi
    cc -std=c11 -O2 "$TMP/$id.c" -o "$TMP/$id" 2>/dev/null || { echo "[$id] does not compile"; return; }
    sed "s|^BIN=.*|BIN=$TMP/$id|" tests/run_tests.sh > "$TMP/$id.sh"
    out=$(sh "$TMP/$id.sh" 2>&1)
    nfail=$(echo "$out" | grep -c '^FAIL')
    echo "[$id] $desc -> detected by $nfail failing checks; first report:"
    echo "$out" | grep -m1 -A3 '^FAIL' | sed 's/^/    /'
}
mutate M1 "reloaded page keeps old dirty bit (no reset on load)" \
  's|dirty\[slot\] = 0;  *\/\* \[A2\] loaded|/*M1*/;/*|'
mutate M2 "a read clears the dirty bit (dirty = op==W)" \
  "s|if (refs\[t\].op == 'W') dirty\[slot\] = 1;|dirty[slot] = (refs[t].op == 'W');|"
mutate M3 "LRU recency not updated on hits (only on load)" \
  's|last\[slot\] = t; r\[slot\] = 1;|r[slot] = 1; if (miss) last[slot] = t;|'
mutate M4 "OPT tie-break picks highest frame index (>= instead of >)" \
  's|if (next > far)|if (next >= far)|'
mutate M5 "writeback counted for every eviction, dirty or not" \
  's|if (dirty\[slot\]) { wb = 1; writebacks++; }|{ wb = 1; writebacks++; }|'
