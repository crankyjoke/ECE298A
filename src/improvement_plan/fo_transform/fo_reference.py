"""Reference for this repository's educational classical hybrid FO profile.

This is not standardized RSA padding and makes no production security claim.
Keccak25-7 is the default toy hash. SHA-256 remains an optional legacy profile.
"""
import hashlib
import secrets
from functools import lru_cache


@lru_cache(maxsize=65536)
def keccak_f25(state):
    """Full Keccak-f[25]; array equations and LFSR round-constant generator."""
    a=[[state >> (x+5*y) & 1 for y in range(5)] for x in range(5)]
    lfsr=1
    for _ in range(12):
        c=[a[x][0]^a[x][1]^a[x][2]^a[x][3]^a[x][4] for x in range(5)]
        b=[[0]*5 for _ in range(5)]
        for x in range(5):
            for y in range(5):
                b[y][(2*x+3*y)%5]=a[x][y]^c[(x-1)%5]^c[(x+1)%5]
        a=[[b[x][y]^((1^b[(x+1)%5][y])&b[(x+2)%5][y])
            for y in range(5)] for x in range(5)]
        # Advance all seven LFSR positions per round; only j=0 fits a 1-bit lane.
        a[0][0]^=lfsr&1
        for _ in range(7):
            lfsr=((lfsr<<1) ^ (0x171 if lfsr&0x80 else 0))&0xff
    return sum(a[x][y] << (x+5*y) for x in range(5) for y in range(5))


def tiny_hash7(kind, seed, message=0):
    """Repository-specific rate-7/capacity-18 sponge; LSB-first with pad10*1."""
    if kind not in (0,1) or not 0<=seed<128 or not 0<=message<128:
        raise ValueError("Keccak25-7 requires seven-bit inputs")
    bits=[kind]+[(seed>>i)&1 for i in range(7)]
    if kind:
        bits += [(message>>i)&1 for i in range(7)]
    bits.append(1)
    while (len(bits)+1)%7:
        bits.append(0)
    bits.append(1)
    state=0
    for start in range(0,len(bits),7):
        state=keccak_f25(state ^ sum(bits[start+i]<<i for i in range(7)))
    return state&127


def hash_value(kind, seed, message=0, *, seed_bits=7, message_bits=7, value_bits=7,
               hash_name="tiny"):
    if kind not in (0, 1) or not 0 <= seed < 1 << seed_bits:
        raise ValueError("invalid FO hash request")
    if not 0 <= message < 1 << message_bits or not 1 <= value_bits <= 256:
        raise ValueError("invalid FO hash width or message")
    if hash_name=="tiny":
        if (seed_bits,message_bits,value_bits)!=(7,7,7):
            raise ValueError("Keccak25-7 requires seven-bit seed, message and digest")
        return tiny_hash7(kind,seed,message)
    if hash_name!="sha256":
        raise ValueError("unknown FO hash profile")
    data = (b"FOH1" if kind else b"FOG1") + seed.to_bytes((seed_bits + 7)//8, "big")
    if kind:
        data += message.to_bytes((message_bits + 7)//8, "big")
    if len(data) > 55:
        raise ValueError("hardware supports one SHA-256 block")
    return int.from_bytes(hashlib.sha256(data).digest(), "big") & ((1 << value_bits)-1)


def encrypt(modulus, exponent, message, *, seed=None, seed_bits=7,
            coin_bits=7, message_bits=7, compute=pow, hash_name="tiny"):
    if modulus < 1 << (seed_bits+coin_bits) or exponent <= 0:
        raise ValueError("invalid modulus or public exponent for FO profile")
    if not 0 <= message < 1 << message_bits:
        raise ValueError("message is out of range")
    seed = secrets.randbits(seed_bits) if seed is None else seed
    if not 0 <= seed < 1 << seed_bits:
        raise ValueError("seed is out of range")
    bits=max(message_bits,coin_bits)
    mask=hash_value(0,seed,seed_bits=seed_bits,message_bits=message_bits,value_bits=bits,hash_name=hash_name)
    coins=hash_value(1,seed,message,seed_bits=seed_bits,message_bits=message_bits,value_bits=bits,hash_name=hash_name)
    representative=(seed << coin_bits) | (coins & ((1 << coin_bits)-1))
    # Callback uses Python pow's operand, exponent, modulus argument order.
    return compute(representative,exponent,modulus), message ^ (mask & ((1 << message_bits)-1))


def decrypt(modulus, public_exponent, private_exponent, ciphertext, masked,
            *, seed_bits=7, coin_bits=7, message_bits=7, compute=pow, hash_name="tiny"):
    if modulus < 1 << (seed_bits+coin_bits) or public_exponent <= 0 or private_exponent <= 0:
        return None
    if not 0 <= masked < 1 << message_bits:
        return None
    in_range=0 <= ciphertext < modulus
    representative=compute(ciphertext if in_range else 0,private_exponent,modulus)
    seed=(representative >> coin_bits) & ((1 << seed_bits)-1)
    bits=max(message_bits,coin_bits)
    mask=hash_value(0,seed,seed_bits=seed_bits,message_bits=message_bits,value_bits=bits,hash_name=hash_name)
    candidate=masked ^ (mask & ((1 << message_bits)-1))
    coins=hash_value(1,seed,candidate,seed_bits=seed_bits,message_bits=message_bits,value_bits=bits,hash_name=hash_name)
    encoded=(seed << coin_bits) | (coins & ((1 << coin_bits)-1))
    check=compute(encoded,public_exponent,modulus)
    if not in_range or representative >> (seed_bits+coin_bits) or check != ciphertext:
        return None
    return candidate


def packet_chunks(modulus, public_exponent, seed, message, *, width=28,
                  seed_bits=7, message_bits=7):
    """Encryption-only GPIO packet: header=0, N, e, sigma, m; 7-bit LSF chunks."""
    if width < 14 or width % 7:
        raise ValueError("invalid hardware width")
    chunks=[0]
    for value,bits in ((modulus,width),(public_exponent,width),
                       (seed,seed_bits),(message,message_bits)):
        if not 0 <= value < 1 << bits:
            raise ValueError("packet field exceeds its width")
        chunks.extend((value >> shift)&0x7f for shift in range(0,bits,7))
    return chunks
