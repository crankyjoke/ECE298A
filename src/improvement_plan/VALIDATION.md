# Validation of the improved RSA experiment

Validated locally with Vivado Simulator and Vivado synthesis **2021.2**.
This records functional RTL simulation and FPGA synthesis, not a GF180 physical
implementation, timing signoff, gate-level simulation, or hardware-board test.

## Functional regression

All six final configurations passed:

| WIDTH | WORD_BITS | RSA transactions | Modular multiplication cases | CRT reconstructions |
| --- | --- | --- | --- | --- |
| 21 | 1 | 31 | 57 | 3 |
| 21 | 7 | 59 | 127 | 3 |
| 21 | 8 | 31 | 57 | 3 |
| 28 | 7 | 59 | 134 | 3 |
| 42 | 7 | 59 | 148 | 3 |
| 56 | 7 | 59 | 162 | 3 |
| **Total** | | **298** | **685** | **18** |

Expected results came from Python's arbitrary-precision `pow(m, e, N)` and
`a*b % N`. The testbench drove the external GPIO protocol and checked all
fourteen-bit result words, including the zero padding in the 21-bit case.
CRT reconstruction used actual pairs of residues produced by the HDL, with
two near-maximum-width primes. Both direct reconstruction and the
`crt_modexp` host-driver callback helper were exercised.

The regression also covered zero exponents/messages, e=65537, full-width
exponents and messages, maximum and even moduli, carries/borrows across word
boundaries, pausing ena, ignored premature/extra/busy strobes, repeated frames
without reset, stable DONE, last-word clamping, and reset abort/recovery.

Commands from the repository root (replace the Vivado bin path as needed):

```sh
python src/improvement_plan/test/run_tests.py --simulator vivado --vivado-bin PATH_TO_VIVADO_BIN --widths 21 28 42 56
python src/improvement_plan/test/run_tests.py --simulator vivado --vivado-bin PATH_TO_VIVADO_BIN --widths 21 --word-bits 1 8 --random-cases 12 --mul-cases 30
```

Per-configuration logs, vectors, and JSON results remain under `.build/` and
are ignored by Git. Icarus support is included in the runner, but these
recorded runs used Vivado Simulator.

## Synthesis check

Out-of-context synthesis for `xc7s25csga324-1` passed for the original design
and all three improved widths. The improved designs use WORD_BITS=7.
There were no errors or critical warnings and no inferred latches.
Tool warnings concern constant GPIO-direction outputs, unused GPIO input
bits, zero-length padding when the result exactly fills its output words,
and parallel-synthesis eligibility.

FPGA resource counts are recorded separately from Tiny Tapeout utilization:

| Design | LUTs | Flip-flops |
| --- | --- | --- |
| Original 28-bit N / 14-bit e,m | 153 | 167 |
| Improved 28-bit N,e,m | 216 | 194 |
| Improved 42-bit N,e,m | 278 | 267 |
| Improved 56-bit N,e,m | 381 | 338 |

The improved core adds full-width inputs, a serial arithmetic controller,
repeatable-frame handling, and output-word advancement. Its narrower ALU does
not make the complete design smaller than the original in this FPGA mapping.
These LUT/flip-flop counts cannot be converted directly into GF180 cell area.

**GF180 synthesis, placement/routing, precheck, and gate-level tests are still
required before claiming that a selected width fits a Tiny Tapeout 1x1 tile.**
The root submission manifest and original RTL were not switched to this
experiment. The existing STM32 protocol must be updated before driving it.
