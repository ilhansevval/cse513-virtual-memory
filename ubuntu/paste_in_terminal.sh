# CSE513 A2 - Section 5, self-contained: paste this whole block into an Ubuntu terminal.
# It recreates the two SUPPLIED programs byte-for-byte (sha256 printed for checking) and runs the experiment script.
mkdir -p ~/cse513 && cd ~/cse513 && mkdir -p supplied ubuntu
cat > supplied/first-touch.c <<'CSE513_EOF'
/* Optional bounded observation. Use a fresh process; counters include runtime noise.
 * An anonymous mapping is not the same as a file read. No exact fault count promised.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <unistd.h>
static struct rusage snapshot(void){struct rusage r;if(getrusage(RUSAGE_SELF,&r)){perror("getrusage");exit(1);}return r;}
static void report(const char *label,struct rusage a,struct rusage b){printf("%-18s minor_delta=%ld major_delta=%ld\n",label,b.ru_minflt-a.ru_minflt,b.ru_majflt-a.ru_majflt);}
int main(void){
    long page=sysconf(_SC_PAGESIZE);if(page<=0){fputs("Page size unavailable\n",stderr);return 1;}
    const size_t bytes=16u*1024u*1024u;unsigned long checksum=0;
    printf("pid=%ld page_size=%ld mapping_bytes=%zu\n",(long)getpid(),page,bytes);fflush(stdout);
    struct rusage a=snapshot();
    volatile unsigned char *p=mmap(NULL,bytes,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
    if(p==MAP_FAILED){perror("mmap");return 1;}struct rusage b=snapshot();
    for(size_t i=0;i<bytes;i+=(size_t)page)checksum+=p[i];struct rusage c=snapshot();
    for(size_t i=0;i<bytes;i+=(size_t)page)p[i]=1;struct rusage d=snapshot();
    for(size_t i=0;i<bytes;i+=(size_t)page)p[i]+=1;struct rusage e=snapshot();
    report("mapping only",a,b);report("first read",b,c);report("first write",c,d);report("repeat write",d,e);
    printf("checksum=%lu first_byte=%u\n",checksum,(unsigned)p[0]);
    if(munmap((void*)p,bytes)){perror("munmap");return 1;}return 0;
}
CSE513_EOF
cat > supplied/cow-observe.c <<'CSE513_EOF'
/* Optional private-mapping/fork observation. Distinct visible values demonstrate
 * isolation; output alone does not prove which physical frame was copied. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>
int main(void){
    long size=sysconf(_SC_PAGESIZE);if(size<=0)return 1;
    volatile unsigned char *p=mmap(NULL,(size_t)size,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
    if(p==MAP_FAILED){perror("mmap");return 1;}p[0]=7;
    int fd[2];if(pipe(fd)){perror("pipe");return 1;}fflush(NULL);pid_t child=fork();
    if(child<0){perror("fork");return 1;}
    if(child==0){close(fd[0]);p[0]=9;unsigned char value=p[0];ssize_t n=write(fd[1],&value,1);close(fd[1]);_exit(n==1?0:1);}
    close(fd[1]);unsigned char value=0;ssize_t n=read(fd[0],&value,1);close(fd[0]);int status;
    if(waitpid(child,&status,0)<0 || n!=1 || !WIFEXITED(status) || WEXITSTATUS(status)!=0){fputs("Child observation failed\n",stderr);return 1;}
    printf("child_private_value=%u parent_private_value=%u\n",(unsigned)value,(unsigned)p[0]);
    int ok=(value==9 && p[0]==7);munmap((void*)p,(size_t)size);return ok?0:1;
}
CSE513_EOF
cat > ubuntu/run_ubuntu_experiments.sh <<'CSE513_EOF'
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
CSE513_EOF
command -v cc >/dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq build-essential; }
bash ubuntu/run_ubuntu_experiments.sh
echo; echo "Expected sha256: first-touch.c 8654b3dc4b8b46ec86aab3e12caec83e27b4e97e0245bf990a312ee6139e84d8"
echo "                 cow-observe.c 6b644254daedcd09440f556feb145c688ccbccaf03f6b8ef985905044eb3fee7"
