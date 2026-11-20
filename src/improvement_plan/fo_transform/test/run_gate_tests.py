"""Standalone FO GPIO regression against the Tiny Tapeout GF180 netlist."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "test"))
from run_fo_tests import test_vectors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clean", action="store_true")
    args = parser.parse_args()
    work = Path.cwd()
    if args.clean:
        for name in ("results.xml", ".build/gate.vvp", "output/simulation.log"):
            (work / name).unlink(missing_ok=True)
        return
    (work / ".build").mkdir(exist_ok=True)
    (work / "output").mkdir(exist_ok=True)
    vectors = argparse.Namespace(width=28, seed_bits=7, coin_bits=7, message_bits=7, random_cases=0, hash_name="tiny")
    rows, hashes, sha = test_vectors(vectors)
    for name, data in (("fo_vectors.txt", rows), ("fo_hashes.txt", hashes), ("sha_vectors.txt", sha)):
        (work / name).write_text("".join(" ".join(f"{value:x}" for value in row) + "\n" for row in data))
    testsuite = ET.Element("testsuite", name="FO GF180 gate-level", tests="1")
    testcase = ET.SubElement(testsuite, "testcase", name="gpio_encryption_decryption_rejection")
    log = []
    try:
        lib = Path(os.environ["PDK_ROOT"]) / "gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/verilog"
        for path in (lib / "primitives.v", lib / "gf180mcu_fd_sc_mcu7t5v0.v", work / "gate_level_netlist.v"):
            if not path.is_file():
                raise FileNotFoundError(path)
        commands = [
            ["iverilog", "-g2012", "-s", "tb_fo", "-DGL_TEST", "-DFUNCTIONAL",
             "-DUSE_POWER_PINS", "-DSIM", "-DUNIT_DELAY=#1", "-Ptb_fo.EXTERNAL_HASH=0",
             "-Ptb_fo.WIDTH=28", "-Ptb_fo.SEED_BITS=7", "-Ptb_fo.COIN_BITS=7", "-Ptb_fo.MESSAGE_BITS=7",
             "-o", ".build/gate.vvp", str(lib / "primitives.v"),
             str(lib / "gf180mcu_fd_sc_mcu7t5v0.v"), "gate_level_netlist.v", str(ROOT / "test/tb_fo.sv")],
            ["vvp", ".build/gate.vvp"],
        ]
        for command in commands:
            result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=1200)
            log.append(result.stdout)
            print(result.stdout, flush=True)
            if result.returncode:
                raise RuntimeError(f"{command[0]} exited with {result.returncode}")
        marker = f"FO_PASS external=0 cases={len(rows)+1} sha=0"
        if marker not in log[-1]:
            raise AssertionError("Gate simulation did not finish all FO cases")
        ET.SubElement(testcase, "system-out").text = marker
    except Exception as error:
        ET.SubElement(testcase, "failure", message=str(error)).text = "\n".join(log)[-16000:]
        raise
    finally:
        (work / "output/simulation.log").write_text("\n".join(log), encoding="utf-8")
        ET.ElementTree(testsuite).write(work / "results.xml", encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    main()
