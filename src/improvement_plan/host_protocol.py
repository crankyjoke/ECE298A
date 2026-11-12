"""Packing and CRT helpers for an STM32/host driver of the improved core."""

from math import gcd


def transaction_chunks(modulus, exponent, message, width=42):
    """Return N, e, m as least-significant-first seven-bit chunks."""
    if width < 14 or width % 7:
        raise ValueError("width must be at least 14 and a multiple of seven")
    if not 1 < modulus < 1 << width:
        raise ValueError("modulus must satisfy 1 < N < 2**width")
    if not 0 <= exponent < 1 << width:
        raise ValueError("exponent does not fit the core")
    if not 0 <= message < modulus:
        raise ValueError("message must satisfy 0 <= m < N")
    return [
        (value >> shift) & 0x7F
        for value in (modulus, exponent, message)
        for shift in range(0, width, 7)
    ]


def result_from_words(words, width=42):
    """Reassemble the least-significant-first fourteen-bit result stream."""
    if width < 14 or width % 7:
        raise ValueError("width must be at least 14 and a multiple of seven")
    if len(words) != (width + 13) // 14:
        raise ValueError("incorrect number of result words")
    if any(not 0 <= word < 1 << 14 for word in words):
        raise ValueError("result word exceeds fourteen bits")
    result = sum(word << (14 * index) for index, word in enumerate(words))
    if result >= 1 << width:
        raise ValueError("nonzero padding in the final result word")
    return result


def crt_combine(result_p, result_q, p, q):
    """Reconstruct a value modulo p*q from two core results.

    RSA callers must supply distinct odd primes from their key generator.
    This routine only checks the algebraic requirements for CRT.
    """
    if p <= 1 or q <= 1 or gcd(p, q) != 1:
        raise ValueError("CRT moduli must be greater than one and coprime")
    if not 0 <= result_p < p or not 0 <= result_q < q:
        raise ValueError("CRT residues are out of range")
    return result_q + q * (((result_p - result_q) * pow(q, -1, p)) % p)


def crt_modexp(message, exponent, p, q, compute):
    """Use two hardware transactions plus host CRT reconstruction.

    compute(N, e, m) must run a transaction and return the complete result.
    It must support the supplied exponent width. Knowing p and q is required;
    this is a host-assisted demonstrator, not public-key-only encryption.
    """
    if p <= 1 or q <= 1 or gcd(p, q) != 1:
        raise ValueError("CRT moduli must be greater than one and coprime")
    if not 0 <= message < p * q or exponent < 0:
        raise ValueError("message or exponent is out of range")
    result_p = compute(p, exponent, message % p)
    result_q = compute(q, exponent, message % q)
    return crt_combine(result_p, result_q, p, q)
