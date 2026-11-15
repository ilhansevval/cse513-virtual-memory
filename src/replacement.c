/* CSE513 Assignment 2 - extended page-replacement simulator (read/write, dirty pages, cost).
 *
 * ORIGIN / CREDIT
 *   Based on the course-supplied replacement.c (CSE513 Week 6, "deterministic page
 *   replacement, not a kernel model"). The victim-selection logic for FIFO, LRU, OPT and
 *   CLOCK (frame scan, born/last timestamps, OPT look-ahead with lowest-index tie-break,
 *   CLOCK hand/reference-bit sweep) is kept from that file and marked [SUPPLIED].
 *   Everything marked [A2] is new for Assignment 2.
 *
 * [A2] ADDITIONS
 *   - References are page:operation tokens (7:R, 0:W); operation R or W.
 *   - Strict input validation with explanations (frames 1-64, 1-256 references,
 *     pages 0-999, digits only - the supplied parser accepted "+7" and " 7").
 *   - An empty reference list is rejected (the supplied file silently used a default list).
 *   - Dirty bit per frame: a loaded page starts clean, W sets dirty=1, R leaves it unchanged
 *     (hits included); a reloaded page starts clean again.
 *   - Counting of hits, faults, initial fills, evictions and dirty writebacks (writeback
 *     counted only when a dirty victim is evicted; resident dirty pages at the end are
 *     reported separately and are NOT flushed).
 *   - Cost model: total = N*m + F*Tin + D*Tout, m=1us, Tin=Tout=10000us; average = total/N.
 *   - Per-step trace with operation, victim, writeback, frame contents and dirty bits
 *     (CLOCK: reference bits and next hand), as a text table or CSV (--csv).
 *   - Run-time verification of invariants after every step and at the end.
 *
 * Usage: replacement [--csv] [--quiet] [--file PATH] FIFO|LRU|OPT|CLOCK FRAMES [REFS ...]
 *   REFS are page:op tokens; one argument may hold several space-separated tokens.
 *   Exit status: 0 success, 2 invalid input, 3 internal verification failure.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

#define LIMIT 256          /* maximum references   [SUPPLIED value] */
#define MAX_FRAMES 64      /* maximum frames       [SUPPLIED value] */
#define MAX_PAGE 999       /* largest page number  [SUPPLIED value] */
#define COST_M 1L          /* [A2] us per completed reference */
#define COST_TIN 10000L    /* [A2] us per page input (every fault) */
#define COST_TOUT 10000L   /* [A2] us per dirty eviction (writeback) */

enum { FIFO, LRU, OPT, CLOCK };
static const char *names[] = {"FIFO", "LRU", "OPT", "CLOCK"};

typedef struct { int page; char op; } Ref; /* [A2] */

static void usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s [--csv] [--quiet] [--file PATH] FIFO|LRU|OPT|CLOCK FRAMES [REFS ...]\n"
        "  FRAMES: 1-%d.  REFS: 1-%d tokens page:op, page 0-%d, op R or W (e.g. 7:R 0:W).\n",
        prog, MAX_FRAMES, LIMIT, MAX_PAGE);
}

/* [A2] Reject invalid input with an explanation and exit status 2. */
static void reject(const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    fputs("Invalid input: ", stderr); vfprintf(stderr, fmt, ap); fputc('\n', stderr);
    va_end(ap); exit(2);
}

/* [A2] Strict decimal parser: digits only (no sign, spaces or hex), value in [lo, hi].
 * Replaces the supplied strtol-based number(), which accepted "+7" and " 7". */
static int strict_number(const char *s, size_t len, int lo, int hi, const char *what, const char *ctx) {
    if (len == 0) reject("%s is missing in \"%s\"", what, ctx);
    long v = 0;
    for (size_t i = 0; i < len; i++) {
        if (s[i] < '0' || s[i] > '9')
            reject("%s in \"%s\" must contain decimal digits only", what, ctx);
        v = v * 10 + (s[i] - '0');
        if (v > hi) break;
    }
    if (v < lo || v > hi) reject("%s in \"%s\" must be between %d and %d", what, ctx, lo, hi);
    return (int)v;
}

/* [A2] Parse one token of the form page:op. */
static Ref parse_ref(const char *tok) {
    const char *colon = strchr(tok, ':');
    if (!colon) reject("reference \"%s\" must have the form page:op, for example 7:R or 0:W", tok);
    Ref r;
    r.page = strict_number(tok, (size_t)(colon - tok), 0, MAX_PAGE, "page number", tok);
    const char *op = colon + 1;
    if (strlen(op) != 1 || (op[0] != 'R' && op[0] != 'W'))
        reject("operation in \"%s\" must be R (read) or W (write)", tok);
    r.op = op[0];
    return r;
}

/* [A2] Split a string on whitespace and append each token as a reference. */
static void add_tokens(char *text, Ref *refs, int *len) {
    for (char *tok = strtok(text, " \t\r\n"); tok; tok = strtok(NULL, " \t\r\n")) {
        if (*len >= LIMIT) reject("at most %d references are allowed", LIMIT);
        refs[(*len)++] = parse_ref(tok);
    }
}

/* [A2] Read references from a file: whitespace separated, '#' starts a comment line. */
static void read_file(const char *path, Ref *refs, int *len) {
    FILE *f = fopen(path, "r");
    if (!f) reject("cannot open reference file \"%s\"", path);
    char line[4096];
    while (fgets(line, sizeof line, f)) {
        char *hash = strchr(line, '#'); if (hash) *hash = '\0';
        add_tokens(line, refs, len);
    }
    fclose(f);
}

/* ---- simulation state ---- */
static int cap, policy, len;
static Ref refs[LIMIT];
static int frame[MAX_FRAMES], last[MAX_FRAMES], born[MAX_FRAMES], r[MAX_FRAMES]; /* [SUPPLIED] */
static int dirty[MAX_FRAMES]; /* [A2] */
static int hand = 0;          /* [SUPPLIED] */

/* [A2] Invariant checks; a failure is a simulator bug, reported with exit status 3. */
static void fail(int step, const char *what) {
    fprintf(stderr, "VERIFICATION FAILED at step %d: %s\n", step, what); exit(3);
}
static void check_state(int step) {
    for (int i = 0; i < cap; i++) {
        if (frame[i] < -1 || frame[i] > MAX_PAGE) fail(step, "frame holds an impossible page number");
        if (frame[i] < 0 && dirty[i]) fail(step, "an empty frame is marked dirty");
        if (dirty[i] != 0 && dirty[i] != 1) fail(step, "dirty bit is not 0/1");
        if (r[i] != 0 && r[i] != 1) fail(step, "reference bit is not 0/1");
        for (int j = i + 1; j < cap; j++)
            if (frame[i] >= 0 && frame[i] == frame[j]) fail(step, "a page is resident in two frames");
    }
    if (hand < 0 || hand >= cap) fail(step, "clock hand out of range");
    /* capacity: residency is stored only in frame[0..cap-1], so it can never exceed cap */
}

static void fmt_frames(char *out, size_t n, int csv) {
    size_t used = 0; out[0] = '\0';
    for (int i = 0; i < cap; i++) {
        char cell[32];
        if (csv) {
            if (frame[i] < 0) snprintf(cell, sizeof cell, "%s-", i ? " " : "");
            else snprintf(cell, sizeof cell, "%s%d", i ? " " : "", frame[i]);
        } else {
            if (frame[i] < 0) snprintf(cell, sizeof cell, "%s%-7s", i ? " " : "", "-");
            else if (policy == CLOCK) snprintf(cell, sizeof cell, "%s%d(D%d,R%d)", i ? " " : "", frame[i], dirty[i], r[i]);
            else snprintf(cell, sizeof cell, "%s%d(D%d)", i ? " " : "", frame[i], dirty[i]);
            if (policy == CLOCK) { char pad[32]; snprintf(pad, sizeof pad, "%-12s", cell); strcpy(cell, pad); }
            else { char pad[32]; snprintf(pad, sizeof pad, "%-8s", cell); strcpy(cell, pad); }
        }
        size_t l = strlen(cell);
        if (used + l + 1 < n) { memcpy(out + used, cell, l + 1); used += l; }
    }
}
static void fmt_bits(char *out, size_t n, const int *bits, int empty_dash) {
    size_t used = 0; out[0] = '\0';
    for (int i = 0; i < cap && used + 3 < n; i++) {
        if (i) out[used++] = ' ';
        out[used++] = (empty_dash && frame[i] < 0) ? '-' : (char)('0' + bits[i]);
        out[used] = '\0';
    }
}

int main(int argc, char **argv) {
    int csv = 0, quiet = 0, argi = 1; const char *file = NULL;
    /* [A2] options */
    while (argi < argc && strncmp(argv[argi], "--", 2) == 0) {
        if (!strcmp(argv[argi], "--csv")) csv = 1;
        else if (!strcmp(argv[argi], "--quiet")) quiet = 1;
        else if (!strcmp(argv[argi], "--file") && argi + 1 < argc) file = argv[++argi];
        else { usage(argv[0]); reject("unknown option \"%s\"", argv[argi]); }
        argi++;
    }
    if (argc - argi < 2) { usage(argv[0]); reject("policy and frame count are required"); }
    policy = -1;
    for (int i = 0; i < 4; i++) if (!strcmp(argv[argi], names[i])) policy = i; /* [SUPPLIED] */
    if (policy < 0) reject("policy \"%s\" must be FIFO, LRU, OPT or CLOCK", argv[argi]);
    cap = strict_number(argv[argi + 1], strlen(argv[argi + 1]), 1, MAX_FRAMES, "frame count", argv[argi + 1]);
    argi += 2;

    len = 0;
    if (file) read_file(file, refs, &len);
    for (; argi < argc; argi++) {
        char buf[8192];
        if (strlen(argv[argi]) >= sizeof buf) reject("argument too long");
        strcpy(buf, argv[argi]);
        add_tokens(buf, refs, &len);
    }
    /* [A2] The supplied file substituted a default list here; the assignment requires a nonempty sequence. */
    if (len == 0) reject("the reference sequence is empty; give 1-%d page:op tokens", LIMIT);

    for (int i = 0; i < cap; i++) { frame[i] = -1; last[i] = born[i] = r[i] = dirty[i] = 0; }
    long hits = 0, faults = 0, fills = 0, evictions = 0, writebacks = 0; /* [A2] */

    if (csv) puts("step,page,op,result,victim,dirty_writeback,frames,dirty_bits,ref_bits,next_hand");
    else if (!quiet) {
        printf("Policy=%s frames=%d references=%d\n", names[policy], cap, len);
        printf("%-4s %-6s %-5s %-6s %-9s %s%s\n", "step", "ref", "hit?", "victim", "writeback",
               policy == CLOCK ? "frames after access: page(Dirty,Ref)" : "frames after access: page(Dirty)",
               policy == CLOCK ? "  | next hand" : "");
    }

    for (int t = 0; t < len; t++) {
        int page = refs[t].page;
        int slot = -1, victim = -1, miss = 0, wb = 0;
        for (int i = 0; i < cap; i++) if (frame[i] == page) slot = i;               /* [SUPPLIED] */
        if (slot < 0) {
            miss = 1; faults++;
            if (policy == CLOCK) {                                                   /* [SUPPLIED] */
                while (frame[hand] >= 0 && r[hand]) { r[hand] = 0; hand = (hand + 1) % cap; }
                slot = hand; hand = (hand + 1) % cap;
            } else {
                for (int i = 0; i < cap; i++) if (frame[i] < 0) { slot = i; break; }   /* lowest empty frame */
                if (slot < 0) {
                    slot = 0;
                    if (policy == FIFO || policy == LRU) {                           /* [SUPPLIED] */
                        for (int i = 1; i < cap; i++)
                            if ((policy == FIFO ? born[i] : last[i]) < (policy == FIFO ? born[slot] : last[slot])) slot = i;
                    } else {                                                         /* OPT [SUPPLIED] */
                        int far = -1;
                        for (int i = 0; i < cap; i++) {
                            int next = len; /* never used again = farthest */
                            for (int j = t + 1; j < len; j++) if (refs[j].page == frame[i]) { next = j; break; }
                            if (next > far) { far = next; slot = i; } /* strict > keeps lowest index on ties */
                        }
                    }
                }
            }
            victim = frame[slot];
            if (victim >= 0) {                                   /* [A2] eviction accounting */
                evictions++;
                if (dirty[slot]) { wb = 1; writebacks++; }       /* dirty victim: one writeback before reuse */
            } else fills++;                                      /* initial fill is not an eviction */
            frame[slot] = page; born[slot] = t;                  /* [SUPPLIED] */
            dirty[slot] = 0;                                     /* [A2] loaded/reloaded page starts clean */
        } else hits++;
        last[slot] = t; r[slot] = 1;                             /* [SUPPLIED] recency + reference bit */
        if (refs[t].op == 'W') dirty[slot] = 1;                  /* [A2] W sets dirty; R leaves it unchanged */

        check_state(t + 1);

        char fr[1024], db[256], rb[256];
        if (csv) {
            fmt_frames(fr, sizeof fr, 1); fmt_bits(db, sizeof db, dirty, 1); fmt_bits(rb, sizeof rb, r, 0);
            printf("%d,%d,%c,%s,", t + 1, page, refs[t].op, miss ? "FAULT" : "HIT");
            if (victim < 0) printf("-"); else printf("%d", victim);
            printf(",%s,\"%s\",\"%s\",", wb ? "YES" : "NO", fr, db);
            if (policy == CLOCK) printf("\"%s\",%d\n", rb, hand); else printf("-,-\n");
        } else if (!quiet) {
            fmt_frames(fr, sizeof fr, 0);
            char refs_s[16], vic[16];
            snprintf(refs_s, sizeof refs_s, "%d:%c", page, refs[t].op);
            if (victim < 0) strcpy(vic, "none"); else snprintf(vic, sizeof vic, "%d", victim);
            printf("%-4d %-6s %-5s %-6s %-9s %s", t + 1, refs_s, miss ? "FAULT" : "HIT", vic, wb ? "YES" : "no", fr);
            if (policy == CLOCK) printf(" | F%d", hand);
            putchar('\n');
        }
    }

    /* [A2] final verification of the counters */
    if (hits + faults != len) fail(len, "hits + faults != references");
    if (!(writebacks <= evictions && evictions <= faults)) fail(len, "writebacks <= evictions <= faults violated");
    if (evictions != faults - fills) fail(len, "evictions != faults - initial fills");
    if (fills > cap) fail(len, "more initial fills than frames");

    int resident_dirty = 0; char dlist[1024] = ""; size_t dl = 0;
    for (int i = 0; i < cap; i++) if (frame[i] >= 0 && dirty[i]) {
        resident_dirty++;
        dl += (size_t)snprintf(dlist + dl, sizeof dlist - dl, "%s%d", dl ? " " : "", frame[i]);
    }
    long total = len * COST_M + faults * COST_TIN + writebacks * COST_TOUT;
    double avg = (double)total / len;

    const char *pre = csv ? "# " : "";
    if (!csv && !quiet) putchar('\n');
    printf("%spolicy=%s frames=%d references=%d hits=%ld faults=%ld initial_fills=%ld evictions=%ld "
           "dirty_writebacks=%ld final_resident_dirty=%d\n",
           pre, names[policy], cap, len, hits, faults, fills, evictions, writebacks, resident_dirty);
    printf("%sfinal_resident_dirty_pages=[%s] (not flushed, not counted as writebacks)\n", pre, dlist);
    printf("%stotal_time_us=%ld (= %d*%ld + %ld*%ld + %ld*%ld) avg_time_us=%.3f\n",
           pre, total, len, COST_M, faults, COST_TIN, writebacks, COST_TOUT, avg);
    printf("%sverification=PASS (hits+faults=N, writebacks<=evictions<=faults, no duplicate page, "
           "residency<=capacity checked after every step)\n", pre);
    return 0;
}
