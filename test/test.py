# SPDX-License-Identifier: Apache-2.0
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly


@cocotb.test()
async def test_cpu_demo(dut):
    """Pin-only test shared by RTL and gate-level simulation."""
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())

    async def reset():
        await FallingEdge(dut.clk)
        dut.rst_n.value = 0
        await ClockCycles(dut.clk, 3)
        await ReadOnly()
        assert int(dut.uo_out.value) == 0
        await FallingEdge(dut.clk)
        dut.rst_n.value = 1

    async def check_input(value):
        await FallingEdge(dut.clk)
        dut.ui_in.value = value
        # Allow an in-flight old sample plus a new 13-cycle program loop.
        await ClockCycles(dut.clk, 32)
        await ReadOnly()
        assert int(dut.uo_out.value) == ((value + 5) & 255), (
            f"input={value}, output={dut.uo_out.value}"
        )
        assert int(dut.uio_oe.value) == 0
        assert int(dut.uio_out.value) == 0

    await reset()
    for value in range(256):
        await check_input(value)
    await reset()
    for value in (7, 20, 255, 0):
        await check_input(value)
