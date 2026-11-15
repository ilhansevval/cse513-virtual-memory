#!/bin/bash
# CSE513 Assignment 2, Section 5 - record the environment, compile the two SUPPLIED
# observation programs unchanged, and run each three times as fresh processes.
# Everything is saved under ubuntu/logs/<timestamp>/ (raw output, nothing edited).
# Read-only: changes no kernel setting, does not touch swap, does not exhaust memory.
# Usage (from the project root):  bash ubuntu/run_ubuntu_experiments.sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAMP=$(date +%Y%m%d_%H%M%S)
OUT="$ROOT/ubuntu/logs/$STAMP"
mkdir -p "$OUT" "$ROOT/ubuntu/bin"
ALL="$OUT/all_output.log"

log() { echo "$*" | tee -a "$ALL"; }
cmd() { # run a command, show it, save its output (stdout+stderr) to the combined log
    log ""; log "\$ $*"
    "$@" 2>&1 | tee -a "$ALL"
    return "${PIPESTATUS[0]}"
}

log "=== CSE513 A2 Ubuntu observations, run started $(date -Is) ==="
log "=== 1. Environment ==="
cmd cat /etc/os-release
cmd uname -r
cmd uname -a
cmd getconf PAGESIZE
cmd cc --version || log "!! no C compiler found: install build-essential or use GitHub Codespaces"
cmd cat /proc/version
log ""; log "\$ environment type detection"
if grep -qi microsoft /proc/version 2>/dev/null; then log "detected: WSL (Windows Subsystem for Linux)"; fi
if [ -n "${CODESPACES:-}" ]; then log "detected: GitHub Codespaces (container on a cloud VM)"; fi
if [ -f /.dockerenv ]; then log "detected: container (/.dockerenv present)"; fi
command -v systemd-detect-virt >/dev/null && cmd systemd-detect-virt
log "(read-only settings that can influence fault counts:)"
cmd cat /sys/kernel/mm/transparent_hugepage/enabled
cmd cat /sys/kernel/mm/transparent_hugepage/use_zero_page
cmd free -h
cmd nproc
log ""; log "\$ sha256sum of the supplied programs (must match the course files, unchanged)"
cmd sha256sum "$ROOT/supplied/first-touch.c" "$ROOT/supplied/cow-observe.c"

log ""; log "=== 2. Compile (exact commands from the assignment) ==="
cd "$ROOT/supplied" || exit 1
cmd cc -std=c11 -O2 -Wall -Wextra first-touch.c -o "$ROOT/ubuntu/bin/first-touch"; ft=$?
cmd cc -std=c11 -O2 -Wall -Wextra cow-observe.c -o "$ROOT/ubuntu/bin/cow-observe"; co=$?
log "compile status: first-touch=$ft cow-observe=$co"

log ""; log "=== 3. first-touch: three fresh processes ==="
for i in 1 2 3; do
    log ""; log "--- first-touch run $i ---"
    "$ROOT/ubuntu/bin/first-touch" > "$OUT/first-touch_run$i.txt" 2>&1; st=$?
    cat "$OUT/first-touch_run$i.txt" | tee -a "$ALL"; log "exit status: $st"
done

log ""; log "=== 4. cow-observe: three fresh processes ==="
for i in 1 2 3; do
    log ""; log "--- cow-observe run $i ---"
    "$ROOT/ubuntu/bin/cow-observe" > "$OUT/cow-observe_run$i.txt" 2>&1; st=$?
    cat "$OUT/cow-observe_run$i.txt" | tee -a "$ALL"; log "exit status: $st"
done

log ""; log "=== finished $(date -Is). Logs saved in ubuntu/logs/$STAMP/ ==="
log "Send all_output.log (or the whole folder) back for the report."
