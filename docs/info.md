# RSA FO encryption-only accelerator

## How it works

The 28-bit RSA core implements the encryption half of the hybrid FO demonstration. A small on-chip Keccak-f[25] sponge produces seven-bit hashes. The public modulus/exponent are 28 bits; messages, seeds, coins, and hash outputs are seven bits. This uses a toy randomized RSA encoding and shortened hashes; no production security claim is made. The host generates keys and fresh random seeds. Decryption runs on the receiver, with no private key on chip.

For seed s and message m, the chip computes r=H(s,m), x=(s<<7)|r, c1=pow(x,e,N), and c2=m XOR G(s). G and H use the domain-separated Keccak25-7 profile specified in src/improvement_plan/fo_transform/README.md.

## How to test

Use N >= 2^14, N < 2^28, 0 < e < 2^28, and seven-bit seed/message values. Supply a valid RSA public key; hardware does not check primality. Keep ena=1 during transfers.

1. Hold LOAD=ui[7] and CONTROL=uio[7] low. Assert reset for four clocks, release it, and wait four clocks.
2. Send 11 seven-bit chunks on ui[6:0]: header=0, four chunks of N, four chunks of e, one seed, one message. Multi-chunk values are least-significant chunk first. For each chunk hold data with LOAD low for four clocks, LOAD high for four clocks, then low for four clocks.
3. Pulse CONTROL high for four clocks and low for four clocks, then wait for DONE=uio[6].
4. ERROR=uio[4] means a malformed packet or checked key parameter; all result words are zero on error. HASH_REQUEST=uio[5] stays zero in the default on-chip-hash design.
5. Read word=((uio&0x0f)<<8)|uo. Read three twelve-bit words, least-significant first, pulsing CONTROL between words. Reconstruct packed=word0|(word1<<12)|(word2<<24), c1=packed&((1<<28)-1), and c2=(packed>>28)&127.
6. Compare with fo_reference.py encrypt(), or decrypt and verify on the software receiver. The first LOAD of the next packet begins a new transaction without reset. Frames do not overlap.

Run make -C test for automated GPIO and exhaustive-hash tests. See src/improvement_plan/fo_transform/README.md for Vivado commands and optional hash configurations.

## External hardware

An STM32 supplies the clock, reset, and key/input packets. Hashing is on-chip.
