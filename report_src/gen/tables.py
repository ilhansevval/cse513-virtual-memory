import csv, sys
T="/home/claude/cse513-a2/traces/"
def rows(tag): return [l for l in open(T+tag+".csv") if not l.startswith("#")]
def table(tag, hand_steps, label, caption, clock=False):
    rd=list(csv.DictReader(rows(tag)))
    n=len(rd[0]["frames"].split())
    cols="r c c r c "+"c "*n+("c c " if clock else "")+"c"
    hdr=["Step","Ref","H/F","Vic.","WB"]+[f"F{i}" for i in range(n)]+(["R bits","Hand"] if clock else [])+["Hand calc."]
    out=[r"\begin{table}[!t]",r"\renewcommand{\arraystretch}{1.05}",r"\setlength{\tabcolsep}{3.2pt}",
         r"\caption{"+caption+"}",r"\label{"+label+"}",r"\centering\footnotesize",
         r"\begin{tabular}{"+cols+"}",r"\toprule"," & ".join(hdr)+r" \\",r"\midrule"]
    for r in rd:
        fr=r["frames"].split(); db=r["dirty_bits"].split()
        cells=["--" if p=="-" else (p+r"$^{\ast}$" if db[i]=="1" else p) for i,p in enumerate(fr)]
        step=int(r["step"])
        line=[r["step"],f"{r['page']}:{r['op']}","F" if r["result"]=="FAULT" else "H",
              "--" if r["victim"]=="-" else r["victim"], "yes" if r["dirty_writeback"]=="YES" else "--"]+cells
        if clock: line+=[r["ref_bits"].replace(" ",""), f"F{r['next_hand']}"]
        line.append(r"\checkmark" if step<=hand_steps else "")
        out.append(" & ".join(line)+r" \\")
        if step==hand_steps and hand_steps<len(rd): out.append(r"\midrule")
    out+= [r"\bottomrule",r"\end{tabular}",r"\end{table}"]
    return "\n".join(out)
specs=[("A_FIFO_3",8,"tab:afifo","FIFO on Workload A, 3 frames: simulator trace (steps 1--8 also calculated by hand)",False),
("A_LRU_3",8,"tab:alru","LRU on Workload A, 3 frames: simulator trace (steps 1--8 also calculated by hand)",False),
("A_OPT_3",8,"tab:aopt","OPT on Workload A, 3 frames: simulator trace (steps 1--8 also calculated by hand)",False),
("A_CLOCK_3",8,"tab:aclock","CLOCK on Workload A, 3 frames: simulator trace (steps 1--8 also calculated by hand)",True),
("B_FIFO_3",12,"tab:bfifo3","FIFO on Workload B, 3 frames: hand-calculated and simulator trace",False),
("B_FIFO_4",12,"tab:bfifo4","FIFO on Workload B, 4 frames: hand-calculated and simulator trace",False),
("T1_dirty_FIFO_2",7,"tab:t1","Test 1, dirty state (FIFO, 2 frames): hand-calculated and simulator trace",False)]
for tag,h,l,c,ck in specs:
    open(f"/home/claude/report/gen/{tag}.tex","w").write(table(tag,h,l,c,ck))
print("ok")
