/* CSE513 optional practice: deterministic page replacement, not a kernel model.
 * Usage: ./replacement FIFO|LRU|OPT|CLOCK frames [page ...]
 * Empty initial frames. CLOCK: hand starts at 0, moves after insertion;
 * every access sets R=1; scanning clears R=1 and evicts the first R=0.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#define LIMIT 256
static int number(const char *s, int max) {
    char *end; errno=0; long v=strtol(s,&end,10);
    if(errno || !*s || *end || v<0 || v>max) {fprintf(stderr,"Invalid number: %s\n",s);exit(2);} return (int)v;
}
int main(int argc,char **argv) {
    const int standard[]={7,0,1,2,0,3,0,4,2,3,0,3,2,1,2,0,1,7,0,1};
    if(argc<3 || argc>LIMIT+3) {fprintf(stderr,"Usage: %s FIFO|LRU|OPT|CLOCK frames [pages]\n",argv[0]);return 2;}
    int policy=-1;const char *names[]={"FIFO","LRU","OPT","CLOCK"};
    for(int i=0;i<4;i++)if(!strcmp(argv[1],names[i]))policy=i;
    int cap=number(argv[2],64);if(policy<0 || cap==0){fprintf(stderr,"Invalid policy or frame count\n");return 2;}
    int refs[LIMIT],len=argc-3;if(!len){len=(int)(sizeof standard/sizeof standard[0]);memcpy(refs,standard,sizeof standard);}else for(int i=0;i<len;i++)refs[i]=number(argv[i+3],999);
    int frame[64],last[64]={0},born[64]={0},r[64]={0},hand=0,faults=0;
    for(int i=0;i<cap;i++)frame[i]=-1;
    puts("step,page,result,victim,frames,clock_hand,reference_bits");
    for(int t=0;t<len;t++) {
        int slot=-1,victim=-1,miss=0;
        for(int i=0;i<cap;i++)if(frame[i]==refs[t])slot=i;
        if(slot<0) {
            miss=1;faults++;
            if(policy==3){while(frame[hand]>=0 && r[hand]){r[hand]=0;hand=(hand+1)%cap;}slot=hand;hand=(hand+1)%cap;}
            else {
                for(int i=0;i<cap;i++)if(frame[i]<0){slot=i;break;}
                if(slot<0){slot=0;
                    if(policy<2){for(int i=1;i<cap;i++)if((policy==0?born[i]:last[i])<(policy==0?born[slot]:last[slot]))slot=i;}
                    else {int far=-1;for(int i=0;i<cap;i++){int next=len;for(int j=t+1;j<len;j++)if(refs[j]==frame[i]){next=j;break;}if(next>far){far=next;slot=i;}}}
                }
            }
            victim=frame[slot];frame[slot]=refs[t];born[slot]=t;
        }
        last[slot]=t;r[slot]=1;
        printf("%d,%d,%s,",t+1,refs[t],miss?"FAULT":"HIT");if(victim<0)printf("-");else printf("%d",victim);printf(",\"");
        for(int i=0;i<cap;i++){if(i)putchar(' ');if(frame[i]<0)putchar('-');else printf("%d",frame[i]);}printf("\",%d,\"",hand);
        for(int i=0;i<cap;i++){if(i)putchar(' ');printf("%d",r[i]);}puts("\"");
    }
    printf("faults=%d references=%d policy=%s frames=%d\n",faults,len,names[policy],cap);return 0;
}
