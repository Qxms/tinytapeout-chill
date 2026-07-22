# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge, ReadOnly


@cocotb.test()
async def test_counter(dut):

    # Set the clock period to 10 ns (100 MHz)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())


    # Initialize all testbench controlled inputs
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    await RisingEdge(dut.clk)  # Wait for reset to be sampled

    await ReadOnly()  # Wait for the read-only phase of the simulation

    assert dut.uo_out.value == 0  # Check that the output (aka counter) is 0 after reset

    assert dut.uio_out.value == 0  # unused output! should still be 0

    assert dut.uio_oe.value == 0  # set these to 0, should still be

    # ReadOnly() lasts until simulation time advances.  Move to the falling
    # edge before driving reset so this write happens in a writable phase.
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1  # Release reset

    await ClockCycles(dut.clk, 67)  # Wait for 67 clock cycles

    await ReadOnly()  # Let the final nonblocking counter update settle
    assert dut.uo_out.value == 67  # Check the count after 67 clock cycles

    await FallingEdge(dut.clk)
    dut.rst_n.value = 0  # Assert reset again

    await RisingEdge(dut.clk)  # Wait for reset to be sampled
    await ReadOnly()
    assert dut.uo_out.value == 0

    await FallingEdge(dut.clk)
    dut.rst_n.value = 1

    dut._log.info("Test project behavior")

    # Wait for one clock cycle to see the output values
    
