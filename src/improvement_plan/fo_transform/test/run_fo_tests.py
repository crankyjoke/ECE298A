"""Generate independent FO/SHA vectors and simulate the GPIO hardware."""
import argparse
import hashlib
import json
from math import gcd
from pathlib import Path
import random
import re
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
PARENT=ROOT.parent
sys.path.insert(0,str(PARENT/"test"))
from run_tests import find_simulator, run_command, previous_prime
sys.path.insert(0,str(ROOT))
from fo_reference import encrypt, decrypt, hash_value, packet_chunks

SOURCES=[PARENT/name for name in ("rsa_alu.v","rsa_modmul.v","rsa_modexp.v")]
SOURCES += [ROOT/name for name in ("sha256_block.v","fo_hash.v","rsa_adapter.v","fo_engine.v","project.v")]
SOURCES += [ROOT/"test"/"tb_fo.sv"]


def test_vectors(args):
    w,s,r,m=args.width,args.seed_bits,args.coin_bits,args.message_bits
    p=previous_prime((1 << (w//2))-1)
    q=previous_prime(p-2)
    e=65537
    while gcd(e,(p-1)*(q-1)) != 1:
        q=previous_prime(q-2)
    n=p*q
    d=pow(e,-1,(p-1)*(q-1))
    kw=dict(seed_bits=s,coin_bits=r,message_bits=m)
    bits=max(m,r)
    hashes={}
    rows=[]

    def oracle(kind,seed,message=0):
        message=message if kind else 0
        key=(kind,seed,message)
        hashes[key]=hash_value(kind,seed,message,seed_bits=s,message_bits=m,value_bits=bits)
        return hashes[key]

    def add(command,nn,ee,dd,c1,seed,payload):
        accepted=False;output=0
        if command in (0,1) and nn >= 1 << (s+r) and ee>0 and (not command or dd>0):
            if not command:
                mask=oracle(0,seed)&((1<<m)-1)
                coins=oracle(1,seed,payload)&((1<<r)-1)
                result=pow((seed<<r)|coins,ee,nn)
                masked=payload ^ mask
                if (result,masked)!=encrypt(nn,ee,payload,seed=seed,**kw):
                    raise AssertionError("reference encryption mismatch")
                accepted=True;output=result | (masked<<w)
            else:
                representative=pow(c1 if c1<nn else 0,dd,nn)
                recovered=(representative>>r)&((1<<s)-1)
                candidate=payload ^ (oracle(0,recovered)&((1<<m)-1))
                coins=oracle(1,recovered,candidate)&((1<<r)-1)
                accepted=c1<nn and representative>>(s+r)==0 and pow((recovered<<r)|coins,ee,nn)==c1
                output=candidate if accepted else 0
                if decrypt(nn,ee,dd,c1,payload,**kw)!=(candidate if accepted else None):
                    raise AssertionError("reference rejection mismatch")
        rows.append((command,nn,ee,dd,c1,seed,payload,int(accepted),output))

    rng=random.Random(29819)
    messages=[(0,0),((1<<s)-1,(1<<m)-1),(1,65&((1<<m)-1))]
    messages += [(rng.randrange(1<<s),rng.randrange(1<<m)) for _ in range(args.random_cases)]
    for seed,message in messages:
        c1,c2=encrypt(n,e,message,seed=seed,**kw)
        if decrypt(n,e,d,c1,c2,**kw)!=message:
            raise AssertionError("reference round trip failed")
        add(0,n,e,0,0,seed,message)
        add(1,n,e,d,c1,0,c2)
        # Choose a changed symmetric component which must reject even with toy hashes.
        for bit in range(m):
            altered=c2 ^ (1<<bit)
            if decrypt(n,e,d,c1,altered,**kw) is None:
                add(1,n,e,d,c1,0,altered)
                break
        else:
            raise AssertionError("could not construct a rejection fixture")
    c1,c2=encrypt(n,e,23&((1<<m)-1),seed=3,**kw)
    for bit in range(w):
        altered=c1 ^ (1<<bit)
        if decrypt(n,e,d,altered,c2,**kw) is None:
            add(1,n,e,d,altered,0,c2)
            break
    for bit in range(w):
        wrong_d=d ^ (1<<bit)
        if wrong_d>0 and decrypt(n,e,wrong_d,c1,c2,**kw) is None:
            add(1,n,e,wrong_d,c1,0,c2)
            break
    for altered in (n,n+1,pow(1<<(s+r),e,n)):
        add(1,n,e,d,altered,0,c2)
    add(1,n,e,0,c1,0,c2)
    add(0,n,0,0,0,3,23&((1<<m)-1))
    add(0,(1<<(s+r))-1,e,0,0,3,23&((1<<m)-1))
    add(2,n,e,0,0,3,23&((1<<m)-1))
    sha_messages=[b"",b"abc",b"a"*55,bytes(range(55))]
    sha_messages += [rng.randbytes(size) for size in (1,2,7,13,31,54)]
    sha=[]
    for message in sha_messages:
        block=message+b"\x80"+bytes(55-len(message))+(len(message)*8).to_bytes(8,"big")
        sha.append((int.from_bytes(block,"big"),int.from_bytes(hashlib.sha256(message).digest(),"big")))
    return rows,sorted(((*key,value) for key,value in hashes.items())),sha


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator",choices=("auto","icarus","vivado"),default="auto")
    parser.add_argument("--vivado-bin",type=Path)
    parser.add_argument("--width",type=int,default=28)
    parser.add_argument("--seed-bits",type=int,default=7)
    parser.add_argument("--coin-bits",type=int,default=7)
    parser.add_argument("--message-bits",type=int,default=7)
    parser.add_argument("--external-hash",type=int,nargs="+",choices=(0,1),default=[0,1])
    parser.add_argument("--random-cases",type=int,default=12)
    args=parser.parse_args()
    if args.width<21 or args.width>63 or args.width%7 or args.seed_bits+args.coin_bits>=args.width:
        parser.error("test WIDTH must be a multiple of seven in 21..63 and exceed seed+coin widths")
    if min(args.seed_bits,args.coin_bits,args.message_bits)<1 or args.random_cases<0:
        parser.error("invalid bit width or case count")
    simulator,commands=find_simulator(args)
    rows,hashes,sha=test_vectors(args)
    summaries=[]
    for external in args.external_hash:
        build=PARENT/".build"/f"fo_w{args.width}_s{args.seed_bits}_r{args.coin_bits}_m{args.message_bits}_ext{external}_{simulator}"
        build.mkdir(parents=True,exist_ok=True)
        (build/"commands.log").write_text("")
        for name,data in (("fo_vectors.txt",rows),("fo_hashes.txt",hashes),("sha_vectors.txt",sha)):
            (build/name).write_text("".join(" ".join(f"{x:x}" for x in row)+"\n" for row in data),encoding="ascii")
        for command,n,e,d,c1,seed,payload,_,_ in rows:
            if command in (0,1):
                chunks=packet_chunks(command,n,e,d,c1,seed,payload,width=args.width,
                    seed_bits=args.seed_bits,message_bits=args.message_bits)
                assert len(chunks)==1+4*(args.width//7)+(args.seed_bits+6)//7+(args.message_bits+6)//7
        parameters=dict(WIDTH=args.width,SEED_BITS=args.seed_bits,COIN_BITS=args.coin_bits,
                        MESSAGE_BITS=args.message_bits,EXTERNAL_HASH=external)
        started=time.monotonic()
        if simulator=="icarus":
            run_command([commands[0],"-g2012","-Wall","-s","tb_fo",
                *[f"-Ptb_fo.{key}={value}" for key,value in parameters.items()],
                "-o","fo.vvp",*SOURCES],build)
            output,_=run_command([commands[1],"fo.vvp"],build)
        else:
            run_command([commands[0],"--sv","--work","work",*SOURCES],build)
            (build/"xelab.args").write_text("work.tb_fo\n"+"".join(
                f'--generic_top "{key}={value}"\n' for key,value in parameters.items())+
                "--snapshot fo_tb\n--timescale 1ns/1ps\n--mt off\n",encoding="ascii")
            run_command([commands[1],"--file","xelab.args"],build)
            output,_=run_command([commands[2],"fo_tb","--runall","--onerror","quit"],build)
        marker=f"FO_PASS external={external} cases={len(rows)+1} sha={len(sha)}"
        if marker not in output or re.search(r"\b(?:Fatal|FATAL|ERROR):",output):
            raise AssertionError(output)
        summary=dict(width=args.width,external_hash=external,fo_cases=len(rows)+1,
                     sha_cases=len(sha),rejected_cases=sum(not row[-2] for row in rows),
                     hash_fixtures=len(hashes),seconds=round(time.monotonic()-started,2))
        (build/"summary.json").write_text(json.dumps(summary,indent=2)+"\n")
        summaries.append(summary)
        print(json.dumps(summary),flush=True)
    (PARENT/".build"/"fo_summary.json").write_text(json.dumps(summaries,indent=2)+"\n")


if __name__=="__main__":
    main()
