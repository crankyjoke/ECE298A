# FO extension validation

Validated on 2026-11-19 using Vivado Simulator and Vivado synthesis 2021.2.
These checks validate the implemented educational profile; they are not a
security proof, cryptographic certification, GF180 physical flow, or board test.

## Current compact hash profile

The default is now on-chip **Keccak25-7**, using the full 12-round
Keccak-f[25] permutation, a seven-bit rate, 18-bit capacity, pad10*1, and
seven-bit output. This is a repository-specific educational profile. The
results in the later sections describe the earlier SHA-256 configurations.

Vivado Simulator passed **16,513 compact-hash checks**: all 16,384 H(seed,m)
pairs, all 128 G seeds with varying ignored message inputs, and a repeat
after reset. The bench also checks captured request inputs, exact 24/36-cycle
permutation latency, enable pauses, output backpressure, and reset during work.
The independent Python sponge uses array equations and an LFSR-generated
round constant sequence; hardware uses packed bits and a constant decoder.
All 128 output values occur across H's exhaustive input set (102 to 157
inputs per output). These distribution observations are not a security proof.

Both on-chip and external compact-hash FO modes passed **110 FO cases**,
including 48 rejections, with the existing 20 SHA-block checks also passing.
The optional 28-bit SHA-256 profile was rerun in both modes with 68 FO cases
and 20 SHA checks passing.

Vivado synthesis for xc7s25csga324-1 completed with zero errors, critical
warnings, or inferred latches:

| Configuration | LUTs | Flip-flops |
| --- | --- | --- |
| Compact hash alone | 67 | 43 |
| 28-bit FO, on-chip compact hash | 451 | 383 |
| 28-bit FO, on-chip SHA-256 | 919 | 868 |

Reports are in `.build/fo_synthesis_hash7/`. These are FPGA resources;
GF180 tile fit must be measured separately. The earlier 112.272% result
below used external hashing, with no on-chip SHA engine to remove.

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

After reducing the default to 28/7/7/7, the default command was rerun in both
hash modes: **110 additional FO cases**, including 48 rejected cases, and
20 SHA checks passed. The default packet now has 19 loads, three result words,
two hash-request words, and one hash-response load.

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
--hash-name sha256 --width 28 --seed-bits 7 --coin-bits 7 --message-bits 7 --random-cases 5
--hash-name sha256 --width 42 --seed-bits 14 --coin-bits 14 --message-bits 14 --random-cases 12
--hash-name sha256 --width 56 --seed-bits 14 --coin-bits 14 --message-bits 14 --random-cases 5
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
The reduced 28/7/7/7 Arty configurations also synthesized successfully, with
zero inferred latches: external hashing uses **401 LUTs / 349 flip-flops**,
and on-chip hashing uses **919 LUTs / 868 flip-flops**. Those reports are in
`.build/fo_synthesis_w28/`.
The local Vivado checks did not perform GF180 placement/routing, timing signoff,
bitstream programming, or physical I/O testing. GitHub GF180 results are below.

The original RSA RTL and active root info.yaml were left unchanged. The new
top requires the new FO GPIO protocol and an updated STM32 driver.

## GitHub Actions and first GF180 attempt

The [first dedicated FO run](https://github.com/crankyjoke/ECE298A/actions/runs/44658191898)
passed all three Icarus jobs (28, 42, and 56 bits, with both hash modes).
This independently repeats the 246 FO cases and 60 SHA-vector checks on Linux.

The default 42-bit trusted-external-hash design synthesized to GF180 cells,
but its **1x1** hardening attempt failed global placement with `GPL-0301`:
OpenROAD reported **162.397% utilization**, exceeding the available area.
The logged movable cell area was 73,277.971 square micrometres against a core
area of 51,966.970 square micrometres, before further pin-density adjustment.
This is an actual area failure; increasing a placement-density setting cannot
make this configuration fit in one tile.

The default FO configuration has been reduced to **28-bit RSA with 7-bit
seed/coin/message fields**, and the dedicated workflow retains the **1x1**
target. The 42- and 56-bit RTL configurations remain in its test matrix.
This does not change the committed original RSA submission's manifest.
The [reduced 28-bit run](https://github.com/crankyjoke/ECE298A/actions/runs/44660147412)
passed all three RTL jobs, but its 1x1 physical build also failed `GPL-0301`,
at **112.272% utilization**. Initial floorplanning reported 50,395.206 square
micrometres of instances in 51,966.970 square micrometres of core area;
placement's movable area after adjustment was 56,629.048 square micrometres.
Thus the smaller default reduces area substantially but still does not fit
the 1x1 budget. Routing, physical precheck, and gate-level tests were not reached.
Further architectural area reductions or a larger allocation are required.
For subsequent outcomes,
see the [FO hardware workflow](https://github.com/crankyjoke/ECE298A/actions/workflows/fo.yaml).
