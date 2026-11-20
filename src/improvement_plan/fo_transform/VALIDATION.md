# FO extension validation

Validated on 2026-11-19 using Vivado Simulator and Vivado synthesis 2021.2.
These checks validate the implemented educational profile; they are not a
security proof, cryptographic certification, GF180 physical flow, or board test.

## GPIO simulation

| RSA width | Seed/coin/message bits | Hash mode | FO cases | Rejected cases | SHA checks |
| --- | --- | --- | --- | --- | --- |
| 42 | 14 / 14 / 14 | On-chip SHA-256 | 55 | 24 | 10 |
| 42 | 14 / 14 / 14 | Trusted external SHA-256 | 55 | 24 | 10 |
| 28 | 7 / 7 / 7 | On-chip SHA-256 | 34 | 17 | 10 |
| 28 | 7 / 7 / 7 | Trusted external SHA-256 | 34 | 17 | 10 |
| 56 | 14 / 14 / 14 | On-chip SHA-256 | 34 | 17 | 10 |
| 56 | 14 / 14 / 14 | Trusted external SHA-256 | 34 | 17 | 10 |
| **Total** | | | **246** | **116** | **60** |

FO expected answers were generated independently using Python arbitrary-precision
modular exponentiation and hashlib SHA-256. The Verilog testbench drove the
actual seven-bit GPIO packet input, polled status, supplied delayed external
hash responses where required, and read every twelve-bit output word.

Checks cover encryption/decryption round trips; zero and maximum seeds/messages;
modified symmetric ciphertexts; modified RSA ciphertexts; out-of-range RSA
ciphertexts; noncanonical decoded representatives; incorrect private exponents;
missing/invalid key parameters; invalid command headers; output padding;
ena pause/resume; early and surplus strobes; repeated transactions without reset;
held DONE/rejection and last output word; and reset during a hash or partial frame.
Rejected cases returned zero on the result channel. External hash mode exposes
candidate values only through its explicitly trusted hash-service interface.

Each configuration also checked the full 256-bit SHA digest against hashlib
for ten messages, including empty input, abc, 55-byte boundary inputs, and
deterministic random inputs. The same ten vector messages were repeated across
the six configurations: 60 checks, not 60 distinct messages.

Commands are listed in README.md. The additional parameter runs used:

```text
--width 28 --seed-bits 7 --coin-bits 7 --message-bits 7 --random-cases 5
--width 56 --random-cases 5
```

Logs/vectors/summary JSON are under the parent's ignored `.build/` directory,
in directories named `fo_w..._ext..._vivado`. Icarus support is included in the
runner, but these recorded checks used Vivado Simulator.

## FPGA synthesis

Both 42-bit `arty_rsa_fo_top` configurations synthesized successfully for
xc7s25csga324-1, with zero errors, zero critical warnings, and zero inferred
latches. A mixed control/data reset style identified in the initial synthesis
was corrected, then all six simulation configurations and both synthesis
configurations were rerun. The set/reset-priority warning is absent in the
final run. Remaining warnings concern inactive-mode input ports and parallel
synthesis eligibility.

| Configuration | LUTs | Flip-flops |
| --- | --- | --- |
| Trusted external SHA-256 | 580 | 515 |
| On-chip SHA-256 | 1050 | 1055 |

Reports are `.build/fo_synthesis/hash_external_1.rpt` and
`hash_external_0.rpt`, relative to the parent improvement_plan directory.
These are FPGA resource counts, **not estimates of GF180 ASIC area**.
No placement/routing, timing signoff, bitstream programming, or physical I/O
test was performed. Tiny Tapeout 1x1 fit is unestablished for both modes.

The original RSA RTL and active root info.yaml were left unchanged. The new
top requires the new FO GPIO protocol and an updated STM32 driver.
