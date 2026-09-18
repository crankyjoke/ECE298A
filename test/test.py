# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # 10 us period = 100 kHz
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Initial values
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    # Test asynchronous reset
    dut._log.info("Testing reset")
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)

    assert dut.uo_out.value == 0
    assert dut.uio_out.value == 0

    dut.rst_n.value = 1

    # Test synchronous load
    dut._log.info("Testing synchronous load")

    dut.uio_in.value = 30

    # ui_in[0] = 1: load enabled
    # ui_in[1] = 0: output disabled
    dut.ui_in.value = 0b00000001

    await ClockCycles(dut.clk, 1)

    assert dut.uo_out.value == 30
    assert dut.uio_out.value == 30
    assert dut.uio_oe.value == 0x00

    # Test counting
    dut._log.info("Testing counting")

    # ui_in[0] = 0: load disabled
    # ui_in[1] = 1: output enabled
    dut.ui_in.value = 0b00000010

    await ClockCycles(dut.clk, 1)

    assert dut.uo_out.value == 31
    assert dut.uio_out.value == 31
    assert dut.uio_oe.value == 0xFF

    await ClockCycles(dut.clk, 1)

    assert dut.uo_out.value == 32
    assert dut.uio_out.value == 32

    # Test tri-state output disabling
    dut._log.info("Testing output disable")

    dut.ui_in.value = 0b00000000
    await Timer(1, unit="us")

    assert dut.uio_oe.value == 0x00

    # Test asynchronous reset between clock edges
    dut._log.info("Testing asynchronous reset")

    dut.rst_n.value = 0
    await Timer(1, unit="us")

    # Must reset without waiting for another rising edge
    assert dut.uo_out.value == 0
    assert dut.uio_out.value == 0

    dut.rst_n.value = 1

    # Test 8-bit overflow: 255 + 1 = 0
    dut._log.info("Testing counter overflow")

    dut.uio_in.value = 255
    dut.ui_in.value = 0b00000001  # load enabled

    await ClockCycles(dut.clk, 1)
    assert dut.uo_out.value == 255

    dut.ui_in.value = 0b00000000  # load disabled

    await ClockCycles(dut.clk, 1)
    assert dut.uo_out.value == 0

    dut._log.info("All tests passed")