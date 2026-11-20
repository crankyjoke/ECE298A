# RSA FO encryption-only accelerator

**Team:** Yaron Jing and Derek

The active Tiny Tapeout submission is `tt_um_rsa_fo`: an educational,
encryption-only hybrid Fujisaki-Okamoto demonstration. The normal **gds**
workflow builds this design and publishes its viewer. The old RSA-only top
`tt_um_example` remains in the repository, but is no longer selected by info.yaml.

| Item | Current default |
| --- | --- |
| RSA modulus / public exponent | 28 bits each |
| Message / random seed / encryption coins | 7 bits each |
| Hash | On-chip Keccak25-7: 25-bit state, 7-bit output |
| Ciphertext | 28-bit RSA component plus 7-bit masked message |
| Arithmetic | Shared two-bit adder/subtractor |
| Input packet | 11 seven-bit loads: header=0, N, e, seed, message |
| Output | Three twelve-bit words, least-significant first |
| Clock target | 10 MHz (100 ns constraint) |
| Tile | 1x1, GF180 |

The host supplies the public key, fresh random seeds, clock, and reset.
Decryption and verification run on the receiver in software. There is no
private-key input, on-chip key generation, or TRNG. Transactions run sequentially
and can repeat without resetting. These small parameters are educational and
provide no production-security or CCA-security claim.

See [the chip protocol](docs/info.md) and the
[FO design guide](src/improvement_plan/fo_transform/README.md) for pins, timing,
packet encoding, hash details, and Vivado setup.

## Verification and builds

From the repository root, with Icarus Verilog and Python installed:

```sh
make -C test
```

This runs the active FO GPIO regression and exhaustive seven-bit hash tests,
and writes JUnit results to `test/results.xml`. The normal **gds** workflow
runs the GF180 build, physical precheck, generated-netlist tests, and viewer
publication using the root manifest. **FO hardware** is a manual workflow for
broader width/hash experiments.

The [normal GDS build](https://github.com/crankyjoke/ECE298A/actions/runs/44759635661)
now builds the FO design in 1x1 at 76.468% placement utilization, with physical
precheck and 21 gate-level cases passing. Its
[GDS viewer](https://crankyjoke.github.io/ECE298A/) is published by that workflow. Nonfatal
maximum-slew warnings remain at some corners. See the full
[validation record](src/improvement_plan/fo_transform/VALIDATION.md).

The [original RSA proposal](docs/legacy_rsa_proposal.md) is archived. Original
RTL and standalone benches are retained; use `make -C test -f Makefile.legacy`
for its former cocotb regression.
