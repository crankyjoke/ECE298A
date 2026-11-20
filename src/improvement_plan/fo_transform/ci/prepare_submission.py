"""Select or refresh the FO submission in an explicitly named workspace.

The main submission uses this profile; the experimental workflow can override
the tile allocation in its disposable workspace. No extra Python dependencies.
"""
import argparse
import json
from pathlib import Path
import re

SOURCES = [
    "improvement_plan/rsa_alu.v",
    "improvement_plan/rsa_modmul.v",
    "improvement_plan/fo_transform/sha256_block.v",
    "improvement_plan/fo_transform/tiny_hash7.v",
    "improvement_plan/fo_transform/fo_hash.v",
    "improvement_plan/fo_transform/rsa_adapter.v",
    "improvement_plan/fo_transform/fo_engine.v",
    "improvement_plan/fo_transform/project.v",
]


def manifest(original, tiles):
    if tiles not in ("1x1", "1x2", "2x2"):
        raise ValueError("unsupported FO experiment tile size")
    result = original.replace("\r\n", "\n")
    for key, value in (
        ("title", "RSA FO encryptor"),
        ("description", "Encryption-only FO demo with on-chip Keccak25-7 hashing"),
        ("top_module", "tt_um_rsa_fo"),
        ("tiles", tiles),
        ("clock_hz", 10_000_000),
    ):
        result, count = re.subn(
            rf"^  {key}:.*$", f"  {key}: {json.dumps(value)}", result, flags=re.MULTILINE
        )
        if count != 1:
            raise ValueError(f"expected exactly one project.{key}")
    source_block = "  source_files:\n" + "".join(f'    - "{name}"\n' for name in SOURCES)
    result, count = re.subn(r"^  source_files:\n(?:    -[^\n]*\n)+", source_block, result, flags=re.MULTILINE)
    if count != 1:
        raise ValueError("could not replace the source list")
    labels = {**{f"ui[{i}]": f"CHUNK[{i}]" for i in range(7)}, "ui[7]": "LOAD"}
    labels.update({f"uo[{i}]": f"WORD[{i}]" for i in range(8)})
    labels.update({f"uio[{i}]": f"WORD[{i+8}]" for i in range(4)})
    labels.update({"uio[4]": "ERROR", "uio[5]": "HASH_REQUEST", "uio[6]": "DONE", "uio[7]": "CONTROL"})
    for pin, label in labels.items():
        result, count = re.subn(rf"^  {re.escape(pin)}:.*$", f'  {pin}: "{label}"', result, flags=re.MULTILINE)
        if count != 1:
            raise ValueError(f"expected exactly one {pin} pin description")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--tiles", choices=("1x1", "1x2", "2x2"), default="1x1")
    args = parser.parse_args()
    workspace = args.workspace.resolve()
    for name in SOURCES:
        if not (workspace / "src" / name).is_file():
            raise FileNotFoundError(f"missing FO build source: {name}")
    info = workspace / "info.yaml"
    prepared = manifest(info.read_text(encoding="utf-8"), args.tiles)
    info.write_text(prepared, encoding="utf-8", newline="\n")
    (workspace / "docs" / "info.md").write_text(
        "# RSA FO encryption-only accelerator\n\n"
        "## How it works\n\n"
        "The 28-bit RSA core implements the encryption half of the hybrid FO demonstration. "
        "A small on-chip Keccak-f[25] sponge produces seven-bit hashes. "
        "The public modulus/exponent are 28 bits; messages, seeds, coins, and hash outputs are seven bits. "
        "This uses a toy randomized RSA encoding and shortened hashes; no production security claim is made. "
        "The host generates keys and fresh random seeds. Decryption runs on the receiver, with no private key on chip.\n\n"
        "For seed s and message m, the chip computes r=H(s,m), x=(s<<7)|r, "
        "c1=pow(x,e,N), and c2=m XOR G(s). G and H use the domain-separated Keccak25-7 profile "
        "specified in src/improvement_plan/fo_transform/README.md.\n\n"
        "## How to test\n\n"
        "Use N >= 2^14, N < 2^28, 0 < e < 2^28, and seven-bit seed/message values. "
        "Supply a valid RSA public key; hardware does not check primality. Keep ena=1 during transfers.\n\n"
        "1. Hold LOAD=ui[7] and CONTROL=uio[7] low. Assert reset for four clocks, release it, and wait four clocks.\n"
        "2. Send 11 seven-bit chunks on ui[6:0]: header=0, four chunks of N, four chunks of e, one seed, one message. "
        "Multi-chunk values are least-significant chunk first. For each chunk hold data with LOAD low for four clocks, "
        "LOAD high for four clocks, then low for four clocks.\n"
        "3. Pulse CONTROL high for four clocks and low for four clocks, then wait for DONE=uio[6].\n"
        "4. ERROR=uio[4] means a malformed packet or checked key parameter; all result words are zero on error. "
        "HASH_REQUEST=uio[5] stays zero in the default on-chip-hash design.\n"
        "5. Read word=((uio&0x0f)<<8)|uo. Read three twelve-bit words, least-significant first, "
        "pulsing CONTROL between words. Reconstruct packed=word0|(word1<<12)|(word2<<24), "
        "c1=packed&((1<<28)-1), and c2=(packed>>28)&127.\n"
        "6. Compare with fo_reference.py encrypt(), or decrypt and verify on the software receiver. "
        "The first LOAD of the next packet begins a new transaction without reset. Frames do not overlap.\n\n"
        "Run make -C test for automated GPIO and exhaustive-hash tests. "
        "See src/improvement_plan/fo_transform/README.md for Vivado commands and optional hash configurations.\n\n"
        "## External hardware\n\n"
        "An STM32 supplies the clock, reset, and key/input packets. Hashing is on-chip.\n",
        encoding="utf-8", newline="\n",
    )
    print(f"Selected 28-bit tt_um_rsa_fo, on-chip Keccak25-7, {args.tiles}, 10 MHz target")


if __name__ == "__main__":
    main()
