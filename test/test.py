# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer


async def wait_clock(dut):
    await ClockCycles(dut.clk, 1)
    # Allow the gate-level circuit to settle
    await Timer(1, unit="us")


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    # Asynchronous reset
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)
    await Timer(1, unit="us")

    assert dut.uio_out.value == 0
    assert dut.uo_out.value == 0

    dut.rst_n.value = 1

    # Synchronously load 30
    dut.uio_in.value = 30
    dut.ui_in.value = 0b00000001
    # ui_in[0] = load enable
    # ui_in[1] = output enable

    await wait_clock(dut)

    assert dut.uio_out.value == 30
    assert dut.uio_oe.value == 0x00
    assert dut.uo_out.value == 0

    # Disable load and enable tri-state outputs
    dut.ui_in.value = 0b00000010

    await wait_clock(dut)

    assert dut.uio_out.value == 31
    assert dut.uio_oe.value == 0xFF
    assert dut.uo_out.value == 0

    await wait_clock(dut)

    assert dut.uio_out.value == 32

    # Disable tri-state outputs
    dut.ui_in.value = 0b00000000
    await Timer(1, unit="us")

    assert dut.uio_oe.value == 0x00

    # Test asynchronous reset between clock edges
    dut.rst_n.value = 0
    await Timer(1, unit="us")

    assert dut.uio_out.value == 0
    assert dut.uo_out.value == 0

    dut.rst_n.value = 1

    # Load 255
    dut.uio_in.value = 255
    dut.ui_in.value = 0b00000001

    await wait_clock(dut)

    assert dut.uio_out.value == 255

    # Verify 8-bit overflow: 255 + 1 = 0
    dut.ui_in.value = 0b00000000

    await wait_clock(dut)

    assert dut.uio_out.value == 0
    assert dut.uo_out.value == 0

    dut._log.info("All tests passed")