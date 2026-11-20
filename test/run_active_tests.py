"""Run the active FO submission's GPIO/hash regressions and emit JUnit results."""
import argparse
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
TEST=ROOT/"test"
FO=ROOT/"src/improvement_plan/fo_transform/test"


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator",choices=("auto","icarus","vivado"),default="auto")
    parser.add_argument("--vivado-bin",type=Path)
    parser.add_argument("--clean",action="store_true")
    args=parser.parse_args()
    cases=(("fo_encryption_gpio","run_fo_tests.py"),("hash7_exhaustive","run_hash7_tests.py"))
    if args.clean:
        for path in [TEST/"results.xml",*[TEST/"output"/f"{name}.log" for name,_ in cases]]:
            path.unlink(missing_ok=True)
        return
    (TEST/"output").mkdir(exist_ok=True)
    suite=ET.Element("testsuite",name="Active FO submission",tests=str(len(cases)))
    failed=False
    try:
        for name,script in cases:
            testcase=ET.SubElement(suite,"testcase",name=name)
            command=[sys.executable,str(FO/script),"--simulator",args.simulator]
            if args.vivado_bin:
                command += ["--vivado-bin",str(args.vivado_bin)]
            try:
                result=subprocess.run(command,cwd=ROOT,text=True,stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT,timeout=1200)
                output=result.stdout
                if result.returncode:
                    raise RuntimeError(f"{script} exited with {result.returncode}\n{output}")
            except Exception as error:
                failed=True
                output=str(error)
                ET.SubElement(testcase,"failure",message=str(error).splitlines()[0]).text=output[-16000:]
            else:
                ET.SubElement(testcase,"system-out").text=output
            (TEST/"output"/f"{name}.log").write_text(output,encoding="utf-8")
            print(output,flush=True)
    finally:
        ET.ElementTree(suite).write(TEST/"results.xml",encoding="utf-8",xml_declaration=True)
    if failed:
        raise SystemExit(1)


if __name__=="__main__":
    main()
