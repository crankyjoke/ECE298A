<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->
# RSA Encryptor

## How it works
Input: 14-bit unsigned integers: $m$ (message to encrypt), $e$ (encryption exponent), 28-bit unsigned integer $N$ (modular)

Output : 28-bit unsigned integer $m^{e} \: (mod\:pq)$

Pin map: 





| Tiny Tapeout pin | Direction | Purpose |
|---|---|---|
| `clk` | Input | Circuit clock |
| `rst_n` | Input | Active-low reset; returns loading to the first \(N\) chunk |
| `ena` | Input | Design enable |
| `ui_in[6:0]` | Input | 7-bit input chunk; bit 0 selects the result page after completion |
| `ui_in[7]` | Input | Load strobe |
| `uio[7]` | Input | Start strobe |
| `uio[6]` | Output | `done`: result is valid when high |
| `uio[5:0]` | Output | Output page bits `[13:8]` |
| `uo_out[7:0]` | Output | Output page bits `[7:0]` |

## How to test

Use unsigned inputs with `1 < N < 2^28`, `0 <= e < 2^14`, and
`0 <= m < min(N, 2^14)`. Keep the design selected (`ena = 1`) and provide
the external clock throughout the transaction.

1. Set `LOAD = ui_in[7]` and `START = uio_in[7]` low. Hold `rst_n = 0`
   for four clock cycles, then release it and wait another four cycles.
2. Load the following eight 7-bit chunks on `ui_in[6:0]`, least-significant
   chunk first:

   | LOAD pulse | Data |
   | --- | --- |
   | 1 | `N[6:0]` |
   | 2 | `N[13:7]` |
   | 3 | `N[20:14]` |
   | 4 | `N[27:21]` |
   | 5 | `e[6:0]` |
   | 6 | `e[13:7]` |
   | 7 | `m[6:0]` |
   | 8 | `m[13:7]` |

   For each chunk, set the data with `LOAD` low and wait four clock cycles.
   Keep the data stable, raise `LOAD` for four cycles, then lower it for
   four cycles before sending the next chunk. These intervals allow the
   input synchronizers to capture the data and strobe.
3. After the eighth load, keep `LOAD` low. Raise `START` for four clock
   cycles, then lower it. Poll `DONE = uio_out[6]`; the functional tests
   allow up to 6000 cycles for completion.
4. Keep `LOAD` and `START` low. Set `ui_in[0] = 0`, wait four clock cycles,
   and read the low result page. Set `ui_in[0] = 1`, wait four cycles,
   and read the high result page. Read each 14-bit page as:

   ```text
   page = ((uio_out & 0x3F) << 8) | uo_out
   ciphertext = low_page | (high_page << 14)
   ```

5. Compare the ciphertext against software `pow(m, e, N)`. `DONE` and
   the completed result remain valid until reset. Reset before loading
   another transaction.

For a known example, use `N = 3233`, `e = 17`, and `m = 65`. The eight
input chunks are `33, 25, 0, 0, 17, 0, 65, 0`; the expected ciphertext is
`2790`. With `e = 0`, the expected result is `1` for every valid modulus.

The bidirectional pin directions are fixed by `uio_oe = 0x7F`: bits 0
through 6 are outputs, and bit 7 is the START input. The host must only
drive bit 7 of this bus.

For automated RTL simulation, install Icarus Verilog and the Python
packages in `test/requirements.txt`, then run `make` in the `test/`
directory. The cocotb tests compare 10 fixed and 200 reproducible random
transactions against Python's modular exponentiation.

## External hardware

An STM32 or another GPIO host supplies the input chunks, LOAD, START,
reset, and clock, then reads DONE and the result pages. Connect a common
ground and use logic levels compatible with the Tiny Tapeout carrier.
