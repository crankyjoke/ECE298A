"""Reference for this repository's educational classical hybrid FO profile.

This is not standardized RSA padding and makes no production security claim.
Hash inputs are domain-separated and encoded in fixed-width big-endian bytes.
"""
import hashlib
import secrets


def hash_value(kind, seed, message=0, *, seed_bits=14, message_bits=14, value_bits=14):
    if kind not in (0, 1) or not 0 <= seed < 1 << seed_bits:
        raise ValueError("invalid FO hash request")
    if not 0 <= message < 1 << message_bits or not 1 <= value_bits <= 256:
        raise ValueError("invalid FO hash width or message")
    data = (b"FOH1" if kind else b"FOG1") + seed.to_bytes((seed_bits + 7)//8, "big")
    if kind:
        data += message.to_bytes((message_bits + 7)//8, "big")
    if len(data) > 55:
        raise ValueError("hardware supports one SHA-256 block")
    return int.from_bytes(hashlib.sha256(data).digest(), "big") & ((1 << value_bits)-1)


def encrypt(modulus, exponent, message, *, seed=None, seed_bits=14,
            coin_bits=14, message_bits=14, compute=pow):
    if modulus < 1 << (seed_bits+coin_bits) or exponent <= 0:
        raise ValueError("invalid modulus or public exponent for FO profile")
    if not 0 <= message < 1 << message_bits:
        raise ValueError("message is out of range")
    seed = secrets.randbits(seed_bits) if seed is None else seed
    if not 0 <= seed < 1 << seed_bits:
        raise ValueError("seed is out of range")
    bits=max(message_bits,coin_bits)
    mask=hash_value(0,seed,seed_bits=seed_bits,message_bits=message_bits,value_bits=bits)
    coins=hash_value(1,seed,message,seed_bits=seed_bits,message_bits=message_bits,value_bits=bits)
    representative=(seed << coin_bits) | (coins & ((1 << coin_bits)-1))
    # Callback uses Python pow's operand, exponent, modulus argument order.
    return compute(representative,exponent,modulus), message ^ (mask & ((1 << message_bits)-1))


def decrypt(modulus, public_exponent, private_exponent, ciphertext, masked,
            *, seed_bits=14, coin_bits=14, message_bits=14, compute=pow):
    if modulus < 1 << (seed_bits+coin_bits) or public_exponent <= 0 or private_exponent <= 0:
        return None
    if not 0 <= masked < 1 << message_bits:
        return None
    in_range=0 <= ciphertext < modulus
    representative=compute(ciphertext if in_range else 0,private_exponent,modulus)
    seed=(representative >> coin_bits) & ((1 << seed_bits)-1)
    bits=max(message_bits,coin_bits)
    mask=hash_value(0,seed,seed_bits=seed_bits,message_bits=message_bits,value_bits=bits)
    candidate=masked ^ (mask & ((1 << message_bits)-1))
    coins=hash_value(1,seed,candidate,seed_bits=seed_bits,message_bits=message_bits,value_bits=bits)
    encoded=(seed << coin_bits) | (coins & ((1 << coin_bits)-1))
    check=compute(encoded,public_exponent,modulus)
    if not in_range or representative >> (seed_bits+coin_bits) or check != ciphertext:
        return None
    return candidate


def packet_chunks(command, modulus, public_exponent, private_exponent,
                  ciphertext, seed, payload, *, width=42, seed_bits=14, message_bits=14):
    """GPIO packet: command, N, e, d, c1, sigma, payload; seven-bit LSF chunks."""
    if command not in (0,1) or width < 14 or width % 7:
        raise ValueError("invalid command or hardware width")
    chunks=[command]
    for value,bits in ((modulus,width),(public_exponent,width),(private_exponent,width),
                       (ciphertext,width),(seed,seed_bits),(payload,message_bits)):
        if not 0 <= value < 1 << bits:
            raise ValueError("packet field exceeds its width")
        chunks.extend((value >> shift)&0x7f for shift in range(0,bits,7))
    return chunks
