# Fujisaki-Okamoto hardware demonstrator

This extension implements the **classical hybrid FO control flow**, with an
explicit reject result, around the existing serial RSA engine. It includes
encryption, decryption, hash-derived encryption coins, symmetric masking,
re-encryption, and ciphertext comparison. It is a separate top-level design;
the original RSA tops and root Tiny Tapeout submission manifest are unchanged.

**This is an educational profile, not a standardized or proven-secure RSA-FO
scheme.** In particular its randomized RSA representative encoding is a test
backend, not a proven probabilistic RSA encryption scheme. The default RSA
modulus is only 42 bits, and seeds/coins/masks are only 14 bits. Implementing
the FO control flow does not confer a CCA-security claim on these parameters
or on this encoding. The existing RSA engine also has data-dependent timing;
constant-time execution and complete key-register zeroization are not provided.

The hybrid construction pattern is described in the
[FO H-oracle instantiation paper, section 5.3](https://iacr.org/archive/crypto2005/36210406/36210406.pdf)
and the [original Fujisaki-Okamoto paper](https://doi.org/10.1007/3-540-48405-1_34).
The hardware SHA-256 rounds follow the algorithm in
[FIPS 180-4](https://csrc.nist.gov/pubs/fips/180-4/upd1/final).
The domain tags, shortened lengths, and RSA encoding below are this
repository's explicit demonstration choices.

## Exact profile

Default parameters: WIDTH=42, SEED_BITS=14, COIN_BITS=14, MESSAGE_BITS=14.
Let `BE(x,b)` encode x in `ceil(b/8)` big-endian bytes with unused high bits zero.
Let `low_b` select the least-significant b bits of the SHA-256 digest integer.

```text
G(sigma)    = low_MESSAGE_BITS(SHA256("FOG1" || BE(sigma, SEED_BITS)))
H(sigma,m)  = low_COIN_BITS(SHA256("FOH1" || BE(sigma, SEED_BITS)
                                             || BE(m, MESSAGE_BITS)))

Encrypt(N,e,m,sigma):
    r  = H(sigma,m)
    x  = (sigma << COIN_BITS) | r
    c1 = x**e mod N
    c2 = m XOR G(sigma)
    return (c1,c2)

Decrypt(N,e,d,c1,c2):
    x      = c1**d mod N
    sigma' = (x >> COIN_BITS) & seed_mask
    m'     = c2 XOR G(sigma')
    r'     = H(sigma',m')
    check  = ((sigma' << COIN_BITS) | r')**e mod N
    accept only if c1 < N, x fits SEED_BITS+COIN_BITS, and check == c1
    return m' on acceptance; otherwise reject and output zero
```

The controller suppresses the plaintext result until the re-encryption check
passes. Reject decisions remain on chip even in external-hash mode.
Out-of-range c1 is replaced by zero before feeding the modular multiplier,
and a rejection flag is retained throughout the remaining computation.

The host must generate valid RSA keys and supply fresh random sigma for each
encryption. No TRNG or key generator is included. The profile requires
`N >= 2**(SEED_BITS+COIN_BITS)`, positive public exponent e, and positive private
exponent d for decryption. Hardware does not validate primality or e/d key
consistency. The caller must enforce those requirements. Encoded operands
must fit WIDTH, so `SEED_BITS+COIN_BITS < WIDTH`.

## Hash configurations and area

- `tt_um_rsa_fo` defaults to **EXTERNAL_HASH=1**. The trusted STM32 computes
  SHA-256 in response to requests from the chip. The FO controller and both
  RSA operations remain in hardware. In this mode the STM32 sees recovered
  seeds and candidate plaintext through the hash-service interface and is
  inside the trusted cryptographic boundary.
- `arty_rsa_fo_top` defaults to **EXTERNAL_HASH=0**. The same reusable SHA-256
  engine performs both hashes on the FPGA, with no host hash requests.
- The native `rsa_fo_engine` also defaults to internal hashing and exposes a
  parallel interface for other integrations. Its input operands must remain
  stable through DONE. `clear` aborts/reset-arms its internal services.

The SHA block engine consumes one already-padded 512-bit block, performs 64
rounds, and starts from the standard IV on every request. The hash formatter
supports inputs of at most 55 bytes; it does not implement multi-block SHA.
Its 16-word message schedule and eight working state words alone contain
768 storage bits, before its 256-bit result and the RSA/FO controller.
**An on-chip hash engine cannot be assumed to fit the remaining half of a
Tiny Tapeout tile. External hashing also adds control and storage; GF180
synthesis and physical checks are still required to establish any tile fit.**

## GPIO protocol: new packet format

This is incompatible with both previous RSA GPIO protocols. Update the STM32
driver before selecting this top. LOAD and CONTROL pulses use the same timing:
set data with LOAD low for four clocks, LOAD high for four clocks, then low
for four clocks. Hold CONTROL high for four clocks and low for four clocks.
Change host signals while the clock is low and keep ena=1 during transfers.

| Signal | Meaning |
| --- | --- |
| ui_in[6:0] | Seven-bit input data |
| ui_in[7] | LOAD rising-edge strobe |
| uio_in[7] | CONTROL: START, or advance an output word |
| uio_out[6] | DONE |
| uio_out[5] | HASH_REQUEST pending (external-hash mode only) |
| uio_out[4] | REJECTED; meaningful when DONE=1 |
| uio_out[3:0], uo_out[7:0] | Twelve-bit output word |
| uio_oe | 0x7F, with uio[6:0] outputs and uio[7] input |

Reset with LOAD and CONTROL low for four clocks, release reset, and wait four
clocks. Send the following packet, then pulse CONTROL to start:

| Field | Default seven-bit chunks | Encoding |
| --- | --- | --- |
| Command | 1 | 0=encrypt, 1=decrypt; other values reject |
| N | 6 | Least-significant chunk first |
| e | 6 | Least-significant chunk first |
| d | 6 | Use zero for encryption |
| c1 | 6 | Use zero for encryption |
| sigma | 2 | Fresh random seed for encryption; zero for decryption |
| Payload | 2 | m for encryption, c2 for decryption |

The default frame has **29 LOAD pulses**. In general it has
`1+4*(WIDTH/7)+ceil(SEED_BITS/7)+ceil(MESSAGE_BITS/7)` pulses.
The host must zero padding bits in the final seed/payload chunks.
START before a full packet, and extra LOADs after a full packet but before
START, are ignored. Ordinary packet loads during computation are ignored;
LOAD is instead a hash response while HASH_REQUEST is asserted.

While computing, poll status:

1. If HASH_REQUEST=1, service the hash request as below.
2. If DONE=1, read the result words. REJECTED=0 means accepted; REJECTED=1
   means all result words are zero.
3. Otherwise wait; no result plaintext is released on the result channel.

Read words as `word=((uio_out & 0x0F)<<8)|uo_out`. The first word is already
selected; pulse CONTROL between words. Extra CONTROL pulses clamp at the
last word. Data is least-significant-word first.

The result has `ceil((WIDTH+MESSAGE_BITS)/12)` words: **five by default**.
For encryption, reconstruct `packed=c1|(c2<<WIDTH)`. For decryption, packed
is the plaintext m on success. Unused high output bits are zero.
DONE and its decision remain held. The first LOAD of the next packet clears
them and begins a new packet without a reset. Frames do not overlap; there
is no input FIFO. Reset aborts loading, computation, and pending hashes.

### Servicing a hash request on STM32

Read `ceil((1+SEED_BITS+MESSAGE_BITS)/12)` words: **three by default**.
Reconstruct:

```text
request = sigma | (message << SEED_BITS)
                | (kind << (SEED_BITS+MESSAGE_BITS))
```

`kind=0` selects G and message is zero. `kind=1` selects H.
Compute the corresponding SHA-256 using the exact domain/byte encoding above,
and return its low `max(MESSAGE_BITS,COIN_BITS)` bits using LOAD pulses with
seven-bit chunks, least-significant first: **two LOAD pulses by default**.
No separate CONTROL acknowledgement is needed for a hash response. The request
is consumed automatically. Poll status again; the next request can follow
quickly, so do not rely on observing a falling edge of HASH_REQUEST.
Never send a new operation packet while a hash request is pending.

`fo_reference.py` contains matching hash and packet-packing helpers. Its
`encrypt` and `decrypt` functions are independent Python references; a rejected
decryption returns `None`. They do not implement an STM32 GPIO transport.

## Files and running in Vivado

Design Sources are:

```text
../rsa_alu.v
../rsa_modmul.v
../rsa_modexp.v
sha256_block.v
fo_hash.v
rsa_adapter.v
fo_engine.v
project.v
arty_rsa_fo_top.v    (only needed for the Arty wrapper)
```

For an Arty S7-25 RTL project, select device xc7s25csga324-1 and top
`arty_rsa_fo_top`. Its external ports match the existing Arty RSA wrapper, so
the matching `arty_rsa.xdc` can be used. `result_high[5]` is now HASH_REQUEST,
`result_high[4]` is REJECTED, and only result_high[3:0] are data. The LEDs show
DONE, HASH_REQUEST, REJECTED, and asserted reset. Run Synthesis, Implementation,
and bitstream generation, checking timing and DRC before programming.
Board programming and physical I/O have not been validated for this extension.

From the repository root, the tested simulator command is:

```powershell
python src/improvement_plan/fo_transform/test/run_fo_tests.py --simulator vivado --vivado-bin "D:/Xillinx/Vivado/2021.2/bin"
```

This exercises the actual GPIO hardware with both hash modes and checks SHA
against Python hashlib. The runner also supports Icarus Verilog on PATH:

```sh
python src/improvement_plan/fo_transform/test/run_fo_tests.py --simulator icarus
```

The test files are simulation-only. Vectors, logs, snapshots, and result JSON
go under the parent's ignored `.build/` directory. Do not add testbench or
Python files to Design Sources. `test/check_synthesis.tcl` optionally checks
both Arty hash configurations and produces FPGA resource reports under
`.build/fo_synthesis/`. It does not establish Tiny Tapeout area/timing.

To select the Tiny Tapeout design later, set the manifest top to
`tt_um_rsa_fo`, list the three parent RSA arithmetic files plus the five FO
files (excluding the Arty wrapper), update the pin descriptions to this
protocol, and run the GF180 flow. This extension does not change that active
submission configuration automatically.

See `VALIDATION.md` for the completed simulation and synthesis checks.

## GitHub Actions

The separate **FO hardware** workflow tests 28-, 42-, and 56-bit configurations
with Icarus and both hash modes. After those pass, it attempts a GF180 physical
build of the default 42-bit external-hash top. This build selects the FO source
list and pin map only in the runner workspace; the committed root info.yaml
continues to select the original RSA core. Precheck and a dedicated FO GPIO
gate-level regression follow a successful physical build.

Push-triggered physical builds use 1x1 tiles. A manual workflow run can select
1x2 or 2x2 for an explicitly larger experiment. A successful RTL test does not
establish physical fit. Build logs and the generated FO manifest are uploaded
even when hardening fails. The standalone gate-level regression uses a slow
functional clock and the generated netlist; it does not replace timing signoff.
