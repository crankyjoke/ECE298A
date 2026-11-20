# FO encryption-only hardware demonstrator

The chip implements the **encryption half** of this repository's educational
hybrid Fujisaki-Okamoto profile: hash-derived encryption coins, randomized RSA
encoding, and symmetric masking. It accepts a public key, seed, and message,
and produces the ciphertext pair `(c1,c2)`. Decryption and ciphertext verification
run on the receiver in software. There is no private-key input, RSA decryption,
plaintext recovery, or re-encryption comparison in this hardware.

The original RSA tops and root Tiny Tapeout submission manifest are unchanged.
This extension is a separate top named `tt_um_rsa_fo`.

This is a demonstration, not standardized RSA padding or a proven-secure
RSA-FO scheme. The RSA modulus is 28 bits and seeds/coins/messages/hashes are
seven bits. A seven-bit hash has only 128 outputs. The RSA engine has
variable execution time, and complete key-register zeroization is not provided.

## Exact encryption profile

Default parameters: `WIDTH=28`, `SEED_BITS=7`, `COIN_BITS=7`, `MESSAGE_BITS=7`,
`SMALL_HASH=1`, `EXTERNAL_HASH=0`. The repository-specific hash is called
**Keccak25-7**; it uses the full twelve-round
[Keccak-f[25] permutation](https://keccak.team/keccakp.html), rather than SHA-3
or SHAKE. Let `bits7(x)` mean the bits of x, least-significant bit first.

```text
G(sigma)   = K25(0 || bits7(sigma))
H(sigma,m) = K25(1 || bits7(sigma) || bits7(m))

K25(M):
    append pad10*1 to make the bit length a multiple of seven
    S = 0                        # 25-bit state, rate 7, capacity 18
    for each seven-bit block B, first input bit at B bit zero:
        S = Keccak-f[25](S XOR B) # all 12 rounds; B affects state bits 0..6
    return S & 0x7f

Encrypt(N,e,m,sigma):
    r  = H(sigma,m)
    x  = (sigma << COIN_BITS) | r
    c1 = x**e mod N
    c2 = m XOR G(sigma)
    return (c1,c2)
```

The host supplies valid RSA public keys and a fresh random seed for each
encryption. There is no key generator or TRNG. The hardware checks
`N >= 2**(SEED_BITS+COIN_BITS)` and `e > 0`; the host validates key suitability.
All operands must fit their configured widths, with seed+coin widths below WIDTH.
Inputs of the native `rsa_fo_engine` must remain stable through DONE.

`fo_reference.py` provides encryption plus receiver-side software decryption and
verification. Its decryption helper is not synthesized into the chip. This
construction uses a toy RSA representative encoding, with no CCA-security claim.
The hybrid construction pattern is described in the
[FO H-oracle instantiation paper, section 5.3](https://iacr.org/archive/crypto2005/36210406/36210406.pdf).

## Hash configurations

Both `tt_um_rsa_fo` and `arty_rsa_fo_top` default to on-chip Keccak25-7.
The compact hash captures its input at acceptance, takes 24 permutation cycles
for G or 36 for H, and holds the result until consumed.

- `SMALL_HASH=1`: seven-bit Keccak25-7 inputs and output.
- `SMALL_HASH=0`: optional SHA-256, truncated to the low
  `max(MESSAGE_BITS,COIN_BITS)` bits. G hashes `"FOG1" || BE(seed)`; H hashes
  `"FOH1" || BE(seed) || BE(message)`. BE uses fixed-width big-endian bytes,
  `ceil(bits/8)` bytes per integer. Select this profile for 14-bit fields.
- `EXTERNAL_HASH=1`: a trusted host services hash requests using the selected
  profile. The default `EXTERNAL_HASH=0` performs all hashing on chip.

Changing hash profiles changes ciphertexts; sender and receiver must agree.
SHA-256 supports one padded block (inputs up to 55 bytes), using the algorithm
in [FIPS 180-4](https://csrc.nist.gov/pubs/fips/180-4/upd1/final).

## Encryption-only GPIO protocol

**The packet changed from 19 to 11 loads. Update the host driver.**
It contains no private exponent or ciphertext input. Header 1, which previously
selected decryption, is now an error. All nonzero headers are errors.

Set input data with LOAD low for four clocks, hold LOAD high for four clocks,
then low for four clocks. Hold CONTROL high for four clocks and low for four
clocks. Change host signals while the clock is low and keep ena=1 for transfers.
Reset with LOAD and CONTROL low for four clocks, release reset, and wait four
clocks before loading.

| Signal | Meaning |
| --- | --- |
| ui_in[6:0] | Seven-bit input chunk |
| ui_in[7] | LOAD rising-edge strobe |
| uio_in[7] | CONTROL: start computation, or advance an output word |
| uio_out[6] | DONE |
| uio_out[5] | HASH_REQUEST (external mode only; zero with on-chip hashing) |
| uio_out[4] | ERROR: bad header, padding, or checked key parameter |
| uio_out[3:0], uo_out[7:0] | Twelve-bit output word |
| uio_oe | 0x7F: uio[6:0] outputs, uio[7] input |

| Field | Default seven-bit chunks | Encoding |
| --- | --- | --- |
| Header | 1 | Must be zero |
| N | 4 | Least-significant chunk first |
| e | 4 | Least-significant chunk first |
| sigma | 1 | Fresh random seed |
| m | 1 | Plaintext message |

The default frame has **11 LOAD pulses**. In general the count is
`1+2*(WIDTH/7)+ceil(SEED_BITS/7)+ceil(MESSAGE_BITS/7)`. Zero padding bits in
partial seed/message chunks. Pulse CONTROL after the complete packet.
Early START and surplus loads before START are ignored. Loads during computation
are ignored except when an external hash response is pending.

Poll DONE. On success ERROR=0, and the output is `packed=c1|(c2<<WIDTH)`.
Read `word=((uio_out&0x0f)<<8)|uo_out`, least-significant word first. The first
word is already selected; pulse CONTROL between words. There are
`ceil((WIDTH+MESSAGE_BITS)/12)` words: **three by default**. Padding is zero.
If ERROR=1, all result words are zero. ERROR reports input errors; it does not
report ciphertext verification, since there is no decryption on chip.

DONE and the result stay held. Extra CONTROL pulses clamp at the last word.
The first LOAD of the next packet clears DONE and begins another transaction
without reset. Loading, computation, and reading are sequential, with no FIFO
or overlapping stream. Reset aborts a partial packet or computation. ena pauses
control and arithmetic; transfer strobes only while ena=1.

### Optional external hash service

When HASH_REQUEST=1, read `ceil((1+SEED_BITS+MESSAGE_BITS)/12)` request words
(two by default), advancing with CONTROL. Reconstruct
`request=sigma|(message<<SEED_BITS)|(kind<<(SEED_BITS+MESSAGE_BITS))`.
Kind 0 means G, with message zero; kind 1 means H. Compute the selected hash,
then return its low `max(MESSAGE_BITS,COIN_BITS)` bits through LOAD in seven-bit
LSF chunks (one load by default). No CONTROL acknowledgement is required.
Poll status again; do not depend on a falling edge between hash requests.

## Vivado and tests

For Arty S7-25 select `xc7s25csga324-1` and top `arty_rsa_fo_top`.
Design sources are:

```text
../rsa_alu.v
../rsa_modmul.v
../rsa_modexp.v
sha256_block.v
tiny_hash7.v
fo_hash.v
rsa_adapter.v
fo_engine.v
project.v
arty_rsa_fo_top.v
```

The wrapper ports match the previous Arty XDC. `result_high[5]` is HASH_REQUEST,
`result_high[4]` is ERROR, and [3:0] are output data. LEDs indicate DONE,
HASH_REQUEST, ERROR, and reset. Board programming and physical I/O are untested.

From the repository root:

```powershell
python src/improvement_plan/fo_transform/test/run_fo_tests.py --simulator vivado --vivado-bin "D:/Xillinx/Vivado/2021.2/bin"
python src/improvement_plan/fo_transform/test/run_hash7_tests.py --simulator vivado --vivado-bin "D:/Xillinx/Vivado/2021.2/bin"
```

Both runners also support `--simulator icarus`. The encryption regression checks
GPIO results against Python pow/hash references, validates software receiver
round trips, exercises bad inputs including the removed decrypt command, and
checks enable pauses, repeated transactions, output paging, and resets.
Select `--hash-name sha256` for the optional legacy hash. The exhaustive hash
regression covers all 16,384 H inputs and all 128 G seeds.

Simulation-only files must not be added to Design Sources. Generated files and
logs are under the parent's ignored `.build/`. The synthesis script
`test/check_synthesis.tcl` compares the two on-chip hashes and writes FPGA
resource reports to `.build/fo_synthesis_encrypt/`. FPGA counts do not establish
GF180 area or timing.

## Tiny Tapeout builds

The dedicated **FO hardware** workflow tests encryption-only configurations at
28 bits with Keccak25-7, and 28/42/56 bits with SHA-256, using internal and
external services. It also runs the exhaustive hash check. It then attempts the
default on-chip-hash design in a 1x1 GF180 tile, followed by precheck and a
GPIO gate-level regression if hardening succeeds.

The workflow selects the FO sources and pin map in its disposable workspace;
the checked-in root info.yaml continues to select the original RSA-only top.
Manual workflow dispatch can choose a larger tile for separate experiments.
The older encrypt/decrypt design exceeded one tile at 125.772% utilization
with the compact hash on chip. The
[encryption-only run](https://github.com/crankyjoke/ECE298A/actions/runs/44663974041)
passed the exhaustive hash and all RTL jobs and lowered placement utilization
to **95.105%**. Global placement proceeded, but detailed placement failed
with `DPL-0036`; the 1x1 physical build is still incomplete.
See VALIDATION.md for current measurements and historical results.
