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
| `ui_in[6:0]` | Input | 7-bit input chunk |
| `ui_in[7]` | Input | Load strobe |
| `uio[7]` | Input | Start strobe |
| `uio[6]` | Output | `done`: result is valid when high |
| `uio[5:0]` | Output | Output page bits `[13:8]` |
| `uo_out[7:0]` | Output | Output page bits `[7:0]` |

## How to test

Explain how to use your project

Choose $2$ 14 bit secret primes (maximum $16,383$) $p$ and $q$, and $e \:s.t.\: gcd(e,\,pq) = 1$ for STM32's main program.
STM32 will upload those values to the chip.

To decrypt the result. STM32 will first compute $d \: s.t. \: de = 1 (mod \, p-1) \: and \: de = 1 (mod \, q-1)$ using extended
Euclidean Algorithm. The decrypted result will be $c^{d} \, (mod \, pq)$

## External hardware

List external hardware used in your project (e.g. PMOD, LED display, etc), if any
