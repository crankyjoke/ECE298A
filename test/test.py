import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge


async def ticks(dut, count=1):
    for _ in range(count):
        await FallingEdge(dut.clk)


async def load_chunk(dut, chunk):
    # Set data while LOAD is low.
    dut.ui_in.value = chunk
    await ticks(dut, 4)

    # Raise LOAD while keeping data unchanged.
    dut.ui_in.value = chunk | 0x80
    await ticks(dut, 4)

    # Lower LOAD.
    dut.ui_in.value = chunk
    await ticks(dut, 4)


async def transaction(dut, modulus, exponent, message):
    # Reset before every transaction.
    dut.ena.value = 1
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ticks(dut, 4)

    assert int(dut.uo_out.value) == 0
    assert int(dut.uio_out.value) == 0
    assert int(dut.uio_oe.value) == 0x7F

    dut.rst_n.value = 1
    await ticks(dut, 4)

    # START before loading must be ignored.
    dut.uio_in.value = 0x80
    await ticks(dut, 4)
    dut.uio_in.value = 0
    await ticks(dut, 4)

    assert not (int(dut.uio_out.value) & 0x40)

    # Load N: four chunks; e: two chunks; m: two chunks.
    for value, chunks in (
            (modulus, 4),
            (exponent, 2),
            (message, 2),
    ):
        for index in range(chunks):
            chunk = (value >> (7 * index)) & 0x7F
            await load_chunk(dut, chunk)

    # Pulse START.
    dut.uio_in.value = 0x80
    await ticks(dut, 4)
    dut.uio_in.value = 0

    # Wait for DONE, with a timeout.
    for cycle in range(6000):
        await ticks(dut)

        if int(dut.uio_out.value) & 0x40:
            break

        # Check that temporarily disabling the core preserves operation.
        if cycle == 20:
            dut.ena.value = 0
            await ticks(dut, 7)
            dut.ena.value = 1
    else:
        raise AssertionError("RSA transaction timed out")

    # Read the two 14-bit result pages.
    pages = []

    for page in (0, 1):
        dut.ui_in.value = page
        await ticks(dut, 4)

        low_bits = int(dut.uo_out.value)
        high_bits = int(dut.uio_out.value) & 0x3F

        pages.append((high_bits << 8) | low_bits)

    actual = pages[0] | (pages[1] << 14)
    expected = pow(message, exponent, modulus)

    assert actual == expected, (
        f"N={modulus}, e={exponent}, m={message}: "
        f"expected {expected}, got {actual}"
    )

    # Additional LOAD/START pulses must not overwrite the result.
    dut.ui_in.value = 0x81
    dut.uio_in.value = 0x80
    await ticks(dut, 5)

    assert int(dut.uio_out.value) & 0x40

    high_page = (
            ((int(dut.uio_out.value) & 0x3F) << 8)
            | int(dut.uo_out.value)
    )
    assert high_page == pages[1]


@cocotb.test()
async def test_rsa(dut):
    dut.clk.value = 0
    dut.ena.value = 1
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    # Slow functional clock for both RTL and gate-level simulation.
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())

    # Each tuple is (N, e, m).
    vectors = [
        (3233, 17, 65),                   # Result: 2790
        (2, 0, 0),                       # Zero exponent
        (2, 1, 1),
        (3, 16383, 2),
        (2**28 - 1, 16383, 16383),
        (2**28 - 1, 8192, 16382),
        (2**27 + 1, 16383, 16383),
        (16381, 0, 123),
        (100, 12345, 0),                  # Zero message
        (100, 8192, 99),
    ]

    # Reproducible random tests, including small and large moduli.
    rng = random.Random(298)

    for index in range(200):
        if index % 2:
            modulus = rng.randint(2, 2**28 - 1)
        else:
            modulus = rng.randint(2, 16384)

        exponent = rng.randrange(16384)
        message = rng.randrange(min(modulus, 16384))

        vectors.append((modulus, exponent, message))

    for vector in vectors:
        await transaction(dut, *vector)