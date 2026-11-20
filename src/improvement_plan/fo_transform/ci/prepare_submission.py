"""Select the FO experiment in an explicitly named disposable CI workspace.

The checked-in root manifest continues to select the original RSA design.
This script has no non-standard Python dependencies.
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
        ("title", "RSA FO experiment"),
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
    info.write_text(prepared, encoding="utf-8")
    (workspace / "docs" / "info.md").write_text(
        "# Educational RSA Fujisaki-Okamoto experiment\n\n"
        "## How it works\n\n"
        "The 28-bit RSA core implements the encryption half of the hybrid FO demonstration. "
        "A small on-chip Keccak-f[25] sponge produces seven-bit hashes. "
        "This uses a toy randomized RSA encoding and shortened hashes; no production security claim is made.\n\n"
        "## How to test\n\n"
        "Run src/improvement_plan/fo_transform/test/run_fo_tests.py. "
        "The encryption-only GPIO protocol, 11-load packet, and twelve-bit result words "
        "are specified in src/improvement_plan/fo_transform/README.md. "
        "ERROR is uio[4], HASH_REQUEST is uio[5], DONE is uio[6], and CONTROL is uio[7]. "
        "No private key or decryption is present on chip.\n\n"
        "## External hardware\n\n"
        "An STM32 supplies the clock, reset, and key/input packets. Hashing is on-chip.\n",
        encoding="utf-8",
    )
    print(f"Selected 28-bit tt_um_rsa_fo, on-chip Keccak25-7, {args.tiles}, 10 MHz target")


if __name__ == "__main__":
    main()
