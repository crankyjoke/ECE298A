"""Exhaustively compare the seven-bit hash hardware with the Python sponge."""
import argparse
from collections import Counter
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/"test"))
from run_tests import find_simulator,run_command
sys.path.insert(0,str(ROOT))
from fo_reference import tiny_hash7


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator",choices=("auto","icarus","vivado"),default="auto")
    parser.add_argument("--vivado-bin",type=Path)
    args=parser.parse_args()
    simulator,commands=find_simulator(args)
    build=ROOT.parent/".build"/f"fo_hash7_{simulator}"
    build.mkdir(parents=True,exist_ok=True)
    (build/"commands.log").write_text("")
    rows=[(0,s,s^0x55,tiny_hash7(0,s)) for s in range(128)]
    rows += [(1,s,m,tiny_hash7(1,s,m)) for s in range(128) for m in range(128)]
    (build/"hash7_vectors.txt").write_text("".join(" ".join(f"{x:x}" for x in row)+"\n" for row in rows))
    sources=[ROOT/"tiny_hash7.v",ROOT/"test/tb_hash7.sv"]
    if simulator=="icarus":
        run_command([commands[0],"-g2012","-Wall","-s","tb_hash7","-o","hash7.vvp",*sources],build)
        output,_=run_command([commands[1],"hash7.vvp"],build)
    else:
        run_command([commands[0],"--sv","--work","work",*sources],build)
        run_command([commands[1],"work.tb_hash7","--snapshot","hash7_tb","--timescale","1ns/1ps","--mt","off"],build)
        output,_=run_command([commands[2],"hash7_tb","--runall","--onerror","quit"],build)
    if f"HASH7_PASS cases={len(rows)+1}" not in output:
        raise AssertionError(output)
    counts=Counter(row[3] for row in rows if row[0])
    summary=dict(cases=len(rows)+1,h_inputs=16384,g_inputs=128,h_distinct_outputs=len(counts),
                 h_min_bucket=min(counts.values()),h_max_bucket=max(counts.values()))
    (build/"summary.json").write_text(json.dumps(summary,indent=2)+"\n")
    print(json.dumps(summary),flush=True)


if __name__=="__main__":
    main()
