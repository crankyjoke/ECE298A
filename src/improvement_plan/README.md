# Wider Tiny Tapeout RSA experiment

This is an independent implementation of `result = message**exponent mod N`.
The default is **42-bit N, 42-bit message, and 42-bit exponent**. All RTL module
names are different from the original design, so both versions can coexist.
The root `info.yaml`, original RTL, and original test Makefile are unchanged.

The multiplier shares one seven-bit adder/subtractor. Additions and reductions
take several cycles, with carry propagated between words. Reduction subtracts N
in place and restores N if the subtraction borrowed. Doubling is a shift.
This avoids a full-width ALU and a separate full-width trial-subtraction bank.
It still needs full-width operand registers, and adds word-selection logic and
control. **Tiny Tapeout area and timing have not been measured for this design;
42-bit or 56-bit fit in a 1x1 tile is not established.**

Parameters on `tt_um_rsa_improved`:

| Parameter | Default | Meaning |
| --- | --- | --- |
| `WIDTH` | 42 | Operand/result width; at least 14 and a multiple of 7 |
| `WORD_BITS` | 7 | Shared ALU word width; from 1 through WIDTH |

Changing `WORD_BITS` changes the area/speed tradeoff, not the GPIO chunk width.
Try WIDTH=28, 42, and 56 in synthesis before selecting a tapeout configuration.
The generic RTL can express wider operands, but parameterization is not proof
of area fit. In particular this is not a self-contained 2048-bit implementation
for one tile.

## GPIO protocol

**This protocol is different from the original eight-load/two-page protocol.
Update the STM32 driver before using it.** There is no UART or input FIFO.

| Pin | Direction | Meaning |
| --- | --- | --- |
| `ui_in[6:0]` | Input | Seven-bit operand chunk |
| `ui_in[7]` | Input | LOAD, captured on a synchronized rising edge |
| `uio_in[7]` | Input | START before computation; NEXT while DONE is high |
| `uio_out[6]` | Output | DONE; first result word is already selected when high |
| `uio_out[5:0]` | Output | Current result word bits 13:8 |
| `uo_out[7:0]` | Output | Current result word bits 7:0 |
| `uio_oe` | Internal output | Always 0x7F: uio[6:0] outputs, uio[7] input |
| `clk`, `rst_n` | Input | External clock and asynchronous active-low reset |
| `ena` | Input | Tiny Tapeout selection enable; keep high for host transfers |

Valid inputs are `1 < N < 2**WIDTH`, `0 <= message < N`, and
`0 <= exponent < 2**WIDTH`. The host must enforce these limits. There is no
invalid-input error output. Zero exponent returns 1 for valid N.

1. Initially hold LOAD and START low, assert reset for four clock cycles, then
   release reset and wait four cycles.
2. Send **N, exponent, message**, in that order. Each operand occupies
   `WIDTH/7` chunks, least-significant chunk first. For each chunk, set data
   with LOAD low for four cycles, hold LOAD high for four cycles with the data
   unchanged, then hold LOAD low for four cycles. Change host signals while
   the clock is low. The spacing lets the two-stage synchronizers settle.
3. Pulse START high for four cycles, then low for four cycles. Poll DONE with
   a timeout. Inputs must not be sent during computation: extra LOAD/START
   pulses while busy are ignored. Extra LOAD pulses after a complete frame
   but before START are also ignored.
4. When DONE rises, read the first word as
   `word = ((uio_out & 0x3F) << 8) | uo_out`. For each additional word, pulse
   START/NEXT high for four cycles, then low for four cycles, then read again.
   There are `ceil(WIDTH/14)` words, least-significant first. Unused high bits
   in the last word are zero. Extra NEXT pulses leave the last word selected.
5. Reassemble `result = sum(word[i] << (14*i))`. DONE stays high and the
   result remains available until reset or the first LOAD of the next frame.
6. **No reset is needed for another transaction.** The first new LOAD begins
   N, clears DONE, zeros the output pins, and restarts the input sequence.

| WIDTH | Chunks per operand | Total LOAD pulses | Result words |
| --- | --- | --- | --- |
| 28 | 4 | 12 | 2 |
| 42 | 6 | 18 | 3 |
| 56 | 8 | 24 | 4 |

Transactions can repeat without reset, but loading, computation, and reading
are sequential. This implementation does not overlap multiple messages or
accept an unlimited stream while computing. Pausing ena freezes arithmetic
and output-word advancement. Strobes occurring entirely while ena=0 are
discarded; only transfer data while the design is selected.

## Host helpers and CRT

`host_protocol.py` provides:

- `transaction_chunks(N, e, m, width)`: validated seven-bit input packing.
- `result_from_words(words, width)`: fourteen-bit output reconstruction and
  final-word padding checks.
- `crt_combine(result_p, result_q, p, q)`: host reconstruction modulo p*q.
- `crt_modexp(message, exponent, p, q, compute)`: two calls to a supplied
  `compute(N, e, m)` hardware-driver callback and then CRT reconstruction.

With two WIDTH-bit primes, the host-assisted system modulus can be up to
2*WIDTH bits. The host must know p and q, reduce each input modulo the
appropriate prime, and combine the two chip results. For example, the default
42-bit core can participate in an up-to-84-bit RSA demonstrator. The chip does
not itself hold or compute modulo the combined 84-bit N. Prime generation,
key validation, padding, and the GPIO driver remain host responsibilities.
The helpers do not generate production cryptographic keys or implement OAEP.

## Run the regression

From the repository root, with Python 3.9+ and Icarus Verilog on PATH:

```sh
python src/improvement_plan/test/run_tests.py
```

No cocotb or other Python package is needed. By default, the runner checks
WIDTH=28, 42, and 56 with a seven-bit ALU. It generates expected answers using
Python `pow(m, e, N)` and integer multiplication, then executes the actual HDL.
It also reconstructs CRT results from the residues returned by the simulator.

An installed Vivado simulator can be used instead:

```sh
python src/improvement_plan/test/run_tests.py --simulator vivado --vivado-bin PATH_TO_VIVADO_BIN
```

Additional arithmetic-word and operand-width combinations can be tested:

```sh
python src/improvement_plan/test/run_tests.py --widths 28 42 56 --word-bits 1 7 8
```

Coverage includes full-width operands and exponents, e=65537, e=0, zero message,
maximum modulus, even moduli, word-boundary carries/borrows, ena pause/resume,
ignored premature/busy/extra strobes, repeated transactions without reset,
all output words and padding, held DONE, and reset during loading/computation.
Logs and JSON summaries are written under the ignored `.build/` directory.
The test-vector generator supports WIDTH up to 63; that is a test fixture limit,
not an extra hardware-width restriction.

The optional `test/check_synthesis.tcl` script synthesizes the original 28-bit
design and the improved 28-, 42-, and 56-bit variants for an Arty S7-25 using
Vivado. Run it from a scratch directory under `.build/` so tool files stay out
of the source tree. Reports go to `.build/fpga_synthesis/`. These FPGA resource
counts check synthesizability; **they are not GF180 area estimates**. The script
also accepts selected variants through `-tclargs improved42 improved56`.

See `VALIDATION.md` for the completed checks and their limits.

## Selecting this design for Tiny Tapeout

After reviewing simulation and measuring GF180 area/timing, change the root
`info.yaml` project entries to the following (retain the other required fields):

```yaml
top_module: "tt_um_rsa_improved"
source_files:
  - "improvement_plan/project.v"
  - "improvement_plan/rsa_loader.v"
  - "improvement_plan/rsa_modexp.v"
  - "improvement_plan/rsa_modmul.v"
  - "improvement_plan/rsa_alu.v"
```

These are project-section entries, so indent them under `project:` in the root
manifest. Use the parameter defaults in `project.v` for the selected tapeout
width. Update the root pin descriptions and documentation for the START/NEXT
protocol, and use the new regression instead of the old protocol testbench.
Changing the active submission configuration is intentionally a separate step.

## Fujisaki-Okamoto extension

The separate `fo_transform/` directory adds a classical hybrid FO hardware
demonstrator, with on-chip or trusted-host SHA-256, decrypt/re-encrypt
verification, explicit rejection, its own GPIO top, and an Arty S7 wrapper.
See `fo_transform/README.md` for its exact educational profile, new packet
format, simulation command, and area/security limits. It does not replace this
folder's existing `tt_um_rsa_improved` top or make the small RSA core secure.
