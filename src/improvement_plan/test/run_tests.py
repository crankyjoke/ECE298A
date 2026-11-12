"""Run self-checking HDL tests with Icarus or an installed Vivado simulator."""

import argparse
import json
import os
from pathlib import Path
import random
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from host_protocol import crt_combine, crt_modexp, result_from_words, transaction_chunks

SOURCES = [ROOT / name for name in (
    "project.v", "rsa_loader.v", "rsa_modexp.v", "rsa_modmul.v", "rsa_alu.v",
)] + [ROOT / "test" / "tb_rsa_improved.sv"]


def is_prime(value):
    """Deterministic Miller-Rabin below 2**64, for reproducible test fixtures."""
    if value < 2:
        return False
    for prime in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
        if value % prime == 0:
            return value == prime
    odd, power = value - 1, 0
    while odd % 2 == 0:
        odd //= 2
        power += 1
    for base in (2, 325, 9375, 28178, 450775, 9780504, 1795265022):
        if base % value == 0:
            continue
        witness = pow(base, odd, value)
        if witness in (1, value - 1):
            continue
        for _ in range(power - 1):
            witness = witness * witness % value
            if witness == value - 1:
                break
        else:
            return False
    return True


def previous_prime(value):
    candidate = value if value % 2 else value - 1
    while not is_prime(candidate):
        candidate -= 2
    return candidate


def vectors(width, random_cases, mul_cases):
    limit = (1 << width) - 1
    rsa = [
        (3233, 17, 65), (2, 0, 0), (2, 1, 1), (2, limit, 1),
        (3, limit, 2), (limit, limit, limit - 1),
        (limit, 1, limit - 1), (limit, 0, limit - 1),
        ((1 << (width - 1)) + 1, 1 << (width - 1), 1 << (width - 2)),
        (100, 12345, 0), (100, 8192, 99),
    ]
    if width >= 21:
        rsa.append((limit, 65537, limit - 2))
    rng = random.Random(298 + width)
    for index in range(random_cases):
        n = rng.randint(2, min(limit, 16384) if index % 3 == 0 else limit)
        rsa.append((n, rng.randrange(limit + 1), rng.randrange(n)))
    crt_cases = []
    p = previous_prime(limit)
    q = previous_prime(p - 2)
    for message in (0, p, p * q - 123):
        exponent = 65537 if width >= 21 else 17
        offset = len(rsa)
        rsa.extend(((p, exponent, message % p), (q, exponent, message % q)))
        crt_cases.append((offset, p, q, message, exponent))
    mul = [
        (2, 0, 0), (2, 1, 1), (3, 2, 2), (limit, limit - 1, limit - 1),
        (limit, 0, limit - 1), (limit, limit - 1, 0),
        (limit, 1 << (width - 1), 1 << (width - 1)),
    ]
    # Exercise carries/borrows crossing seven-bit and configurable word boundaries.
    for boundary in range(1, width):
        n = min(limit, (1 << boundary) + 1)
        mul.append((n, n - 1, n - 1))
    for _ in range(mul_cases):
        n = rng.randint(2, limit)
        mul.append((n, rng.randrange(n), rng.randrange(n)))
    return rsa, mul, crt_cases


def run_command(command, cwd):
    started = time.monotonic()
    completed = subprocess.run(
        [str(arg) for arg in command], cwd=cwd, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=600,
    )
    with (cwd / "commands.log").open("a", encoding="utf-8") as log:
        log.write(f"\n$ {subprocess.list2cmdline([str(arg) for arg in command])}\n{completed.stdout}")
    if completed.returncode:
        raise RuntimeError(f"Command failed ({completed.returncode}): {command[0]}\n{completed.stdout}")
    return completed.stdout, time.monotonic() - started


def find_simulator(args):
    iverilog, vvp = shutil.which("iverilog"), shutil.which("vvp")
    if args.simulator in ("auto", "icarus") and iverilog and vvp:
        return "icarus", (Path(iverilog), Path(vvp))
    if args.simulator == "icarus":
        raise RuntimeError("Add iverilog and vvp to PATH")
    vivado_bin = args.vivado_bin
    if not vivado_bin and os.environ.get("XILINX_VIVADO"):
        vivado_bin = Path(os.environ["XILINX_VIVADO"]) / "bin"
    extension = ".bat" if os.name == "nt" else ""
    commands = tuple(
        Path(vivado_bin) / (name + extension) if vivado_bin else shutil.which(name)
        for name in ("xvlog", "xelab", "xsim")
    )
    if all(command and Path(command).is_file() for command in commands):
        return "vivado", commands
    raise RuntimeError("Install Icarus, or pass --simulator vivado --vivado-bin PATH_TO_VIVADO_BIN")


def run_configuration(width, word_bits, args, simulator, commands):
    build = ROOT / ".build" / f"w{width}_b{word_bits}_{simulator}"
    build.mkdir(parents=True, exist_ok=True)
    (build / "commands.log").write_text("", encoding="utf-8")
    rsa, mul, crt_cases = vectors(width, args.random_cases, args.mul_cases)
    for name, data, expected in (
        ("rsa_vectors.txt", rsa, lambda n, e, m: pow(m, e, n)),
        ("mul_vectors.txt", mul, lambda n, a, b: a * b % n),
    ):
        (build / name).write_text("".join(
            " ".join(f"{value:x}" for value in (*row, expected(*row))) + "\n"
            for row in data
        ), encoding="ascii")
    for n, e, m in rsa:
        chunks = transaction_chunks(n, e, m, width)
        reconstructed = [sum(chunks[field * (width // 7) + index] << (7 * index)
            for index in range(width // 7)) for field in range(3)]
        if reconstructed != [n, e, m]:
            raise AssertionError("Host transaction encoding failed")
    started = time.monotonic()
    if simulator == "icarus":
        compiler, runtime = commands
        run_command([compiler, "-g2012", "-Wall", "-s", "tb_rsa_improved",
            f"-Ptb_rsa_improved.WIDTH={width}", f"-Ptb_rsa_improved.WORD_BITS={word_bits}",
            "-o", "simulation.vvp", *SOURCES], build)
        output, _ = run_command([runtime, "simulation.vvp"], build)
    else:
        compiler, elaborator, runtime = commands
        run_command([compiler, "--sv", "--work", "work", *SOURCES], build)
        # A response file preserves '=' through Vivado's Windows batch launcher.
        (build / "xelab.args").write_text(
            f'work.tb_rsa_improved\n--generic_top "WIDTH={width}"\n'
            f'--generic_top "WORD_BITS={word_bits}"\n'
            '--snapshot improvement_tb\n--timescale 1ns/1ps\n--mt off\n',
            encoding="ascii",
        )
        run_command([elaborator, "--file", "xelab.args"], build)
        output, _ = run_command([runtime, "improvement_tb", "--runall", "--onerror", "quit"], build)
    marker = f"PASS width={width} word_bits={word_bits} rsa={len(rsa)+1} modmul={len(mul)}"
    if marker not in output or re.search(r"\b(?:Fatal|FATAL|ERROR):", output):
        raise AssertionError(f"Simulation failed or did not reach completion:\n{output}")
    actual = [int(value, 16) for _, value in re.findall(r"RSA_RESULT\s+(\d+)\s+([0-9a-fA-F]+)", output)]
    if len(actual) != len(rsa) + 1:
        raise AssertionError("Missing simulated results")
    for result, (n, e, m) in zip(actual, rsa):
        if result != pow(m, e, n):
            raise AssertionError("HDL result differs from Python modular exponentiation")
        words = [(result >> shift) & 0x3FFF for shift in range(0, width, 14)]
        if result_from_words(words, width) != result:
            raise AssertionError("Host result reconstruction failed")
    for offset, p, q, message, exponent in crt_cases:
        reconstructed = crt_combine(actual[offset], actual[offset + 1], p, q)
        if reconstructed != pow(message, exponent, p * q):
            raise AssertionError("CRT using actual HDL results failed")
        replies = iter((offset, offset + 1))

        def simulated_hardware(n, e, m):
            index = next(replies)
            if (n, e, m) != rsa[index]:
                raise AssertionError("CRT callback received incorrect hardware operands")
            return actual[index]

        if crt_modexp(message, exponent, p, q, simulated_hardware) != reconstructed:
            raise AssertionError("Host-assisted CRT callback failed")
    summary = dict(width=width, word_bits=word_bits, simulator=simulator,
        rsa_transactions=len(rsa) + 1, modular_products=len(mul),
        crt_cases=len(crt_cases), elapsed_seconds=round(time.monotonic() - started, 2))
    (build / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary), flush=True)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", choices=("auto", "icarus", "vivado"), default="auto")
    parser.add_argument("--vivado-bin", type=Path)
    parser.add_argument("--widths", nargs="+", type=int, default=[28, 42, 56])
    parser.add_argument("--word-bits", nargs="+", type=int, default=[7])
    parser.add_argument("--random-cases", type=int, default=40)
    parser.add_argument("--mul-cases", type=int, default=100)
    args = parser.parse_args()
    if any(width < 14 or width > 63 or width % 7 for width in args.widths):
        parser.error("test widths must be multiples of seven between 14 and 63")
    if args.random_cases < 0 or args.mul_cases < 0:
        parser.error("case counts must be nonnegative")
    if any(bits < 1 or bits > min(args.widths) for bits in args.word_bits):
        parser.error("word sizes must lie between one and the smallest tested width")
    simulator, commands = find_simulator(args)
    summaries = [run_configuration(width, bits, args, simulator, commands)
        for width in args.widths for bits in args.word_bits]
    (ROOT / ".build" / "summary.json").write_text(json.dumps(summaries, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
