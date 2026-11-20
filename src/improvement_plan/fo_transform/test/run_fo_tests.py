"""Compare encryption-only FO GPIO output with Python; decrypt only in software."""
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
SOURCES += [ROOT/name for name in ("sha256_block.v","tiny_hash7.v","fo_hash.v","rsa_adapter.v","fo_engine.v","project.v")]
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
    kw=dict(seed_bits=s,coin_bits=r,message_bits=m,hash_name=args.hash_name)
    bits=max(m,r)
    hashes={}
    rows=[]

    def oracle(kind,seed,message=0):
        message=message if kind else 0
        key=(kind,seed,message)
        hashes[key]=hash_value(kind,seed,message,seed_bits=s,message_bits=m,value_bits=bits,hash_name=args.hash_name)
        return hashes[key]

    def add(command,nn,ee,seed,payload):
        accepted=command==0 and nn >= 1 << (s+r) and ee>0
        output=0
        if accepted:
            mask=oracle(0,seed)&((1<<m)-1)
            coins=oracle(1,seed,payload)&((1<<r)-1)
            result=pow((seed<<r)|coins,ee,nn)
            masked=payload ^ mask
            if (result,masked)!=encrypt(nn,ee,payload,seed=seed,**kw):
                raise AssertionError("reference encryption mismatch")
            output=result | (masked<<w)
        rows.append((command,nn,ee,seed,payload,int(accepted),output))

    rng=random.Random(29819)
    messages=[(0,0),((1<<s)-1,(1<<m)-1),(1,65&((1<<m)-1))]
    messages += [(rng.randrange(1<<s),rng.randrange(1<<m)) for _ in range(args.random_cases)]
    for seed,message in messages:
        c1,c2=encrypt(n,e,message,seed=seed,**kw)
        if decrypt(n,e,d,c1,c2,**kw)!=message:
            raise AssertionError("reference round trip failed")
        # Decryption is performed only by the software receiver; d is never loaded.
        add(0,n,e,seed,message)
    for ee in (1,17,(1<<w)-1):
        add(0,n,ee,3,23&((1<<m)-1))
    for nn in (1<<(s+r),(1<<w)-1):
        add(0,nn,e,(1<<s)-1,(1<<m)-1)
    # The previous decrypt command is now an invalid header, as are other opcodes.
    for command in (1,2,127):
        add(command,n,e,3,23&((1<<m)-1))
    add(0,n,0,3,23&((1<<m)-1))
    for nn in (0,1,(1<<(s+r))-1):
        add(0,nn,e,3,23&((1<<m)-1))
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
    parser.add_argument("--hash-name",choices=("tiny","sha256"),default="tiny")
    parser.add_argument("--external-hash",type=int,nargs="+",choices=(0,1),default=[0,1])
    parser.add_argument("--random-cases",type=int,default=12)
    args=parser.parse_args()
    if args.width<21 or args.width>63 or args.width%7 or args.seed_bits+args.coin_bits>=args.width:
        parser.error("test WIDTH must be a multiple of seven in 21..63 and exceed seed+coin widths")
    if min(args.seed_bits,args.coin_bits,args.message_bits)<1 or args.random_cases<0:
        parser.error("invalid bit width or case count")
    if args.hash_name=="tiny" and (args.seed_bits,args.coin_bits,args.message_bits)!=(7,7,7):
        parser.error("the tiny hash requires seven-bit seed/coin/message fields")
    simulator,commands=find_simulator(args)
    rows,hashes,sha=test_vectors(args)
    summaries=[]
    for external in args.external_hash:
        build=PARENT/".build"/f"fo_enc_{args.hash_name}_w{args.width}_s{args.seed_bits}_r{args.coin_bits}_m{args.message_bits}_ext{external}_{simulator}"
        build.mkdir(parents=True,exist_ok=True)
        (build/"commands.log").write_text("")
        for name,data in (("fo_vectors.txt",rows),("fo_hashes.txt",hashes),("sha_vectors.txt",sha)):
            (build/name).write_text("".join(" ".join(f"{x:x}" for x in row)+"\n" for row in data),encoding="ascii")
        for command,n,e,seed,payload,_,_ in rows:
            if command==0:
                chunks=packet_chunks(n,e,seed,payload,width=args.width,
                    seed_bits=args.seed_bits,message_bits=args.message_bits)
                assert len(chunks)==1+2*(args.width//7)+(args.seed_bits+6)//7+(args.message_bits+6)//7
        parameters=dict(WIDTH=args.width,SEED_BITS=args.seed_bits,COIN_BITS=args.coin_bits,
                        MESSAGE_BITS=args.message_bits,EXTERNAL_HASH=external,SMALL_HASH=int(args.hash_name=="tiny"))
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
        summary=dict(width=args.width,hash_name=args.hash_name,external_hash=external,fo_cases=len(rows)+1,
                     sha_cases=len(sha),error_cases=sum(not row[-2] for row in rows),
                     hash_fixtures=len(hashes),seconds=round(time.monotonic()-started,2))
        (build/"summary.json").write_text(json.dumps(summary,indent=2)+"\n")
        summaries.append(summary)
        print(json.dumps(summary),flush=True)
    (PARENT/".build"/"fo_summary.json").write_text(json.dumps(summaries,indent=2)+"\n")


if __name__=="__main__":
    main()
