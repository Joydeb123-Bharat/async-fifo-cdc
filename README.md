# Asynchronous FIFO with Gray-Code Pointers

A parameter-free, 16-deep × 32-bit **asynchronous FIFO** in SystemVerilog for safe clock domain crossing (CDC), together with a **layered, self-checking SystemVerilog testbench** (interface, generator, driver, monitor, scoreboard, environment, test) and SVA assertions.

Written by hand, simulated in Vivado XSim 2025.2.

---

## Table of Contents

1. [Overview](#overview)
2. [Key Features](#key-features)
3. [Architecture](#architecture)
4. [Module Descriptions](#module-descriptions)
5. [Top-Level Interface](#top-level-interface)
6. [How the CDC Works](#how-the-cdc-works)
7. [Verification Environment](#verification-environment)
8. [Results](#results)
9. [Running the Simulation](#running-the-simulation)
10. [Repository Structure](#repository-structure)
11. [Known Limitations](#known-limitations)
12. [Roadmap](#roadmap)
13. [Author](#author)

---

## Overview

When data moves between two unrelated clocks, a single bit that changes near the receiving clock edge can go metastable, and a multi-bit value can be captured half-old and half-new. An asynchronous FIFO avoids both problems: the data sits in a dual-port memory, and only the **read and write pointers** cross between domains, as **Gray codes** through **multi-flop synchronizers**. Because a Gray-coded pointer changes by exactly one bit per increment, a synchronizer can only ever capture the old or the new value, never an invalid one.

This project implements that structure with a valid/ready handshake on both sides and verifies it with a constrained-random, scoreboard-checked testbench running on two non-integer-related clocks (10 ns and 13 ns).

## Key Features

- 16 entries × 32-bit data, dual-clock (`wclk` / `rclk`)
- 5-bit binary and Gray pointers (4 address bits + 1 wrap bit)
- Gray pointers **registered before crossing**, then passed through 3-flop synchronizers
- Registered `full` and `empty` flags computed from the **next** pointer values
- Valid/ready handshake on both the write and the read side
- Layered testbench with a scoreboard, directed phases, and SVA assertions
- Everything in plain SystemVerilog, no external libraries, no packages

## Architecture

```
        wclk domain                                       rclk domain
 ┌────────────────────────┐                        ┌────────────────────────┐
 │        write_p         │                        │         Read_p         │
 │                        │                        │                        │
 │  wbin ──► wgray (reg)  │── wgray ──[ 3-FF sync ]──► wsync_3              │
 │     │                  │                        │      │                 │
 │  full flag  ◄─ rsync_3 │◄─[ 3-FF sync ]── rgray ─│  rbin ──► rgray (reg)  │
 │                        │                        │      │                 │
 └───────┬────────────────┘                        │  empty flag ◄─ wsync_3 │
         │ wdata, wpoint[3:0], wvalid              └───────────▲────────────┘
         ▼                                                     │ r_data
 ┌──────────────────────────────────────────────────────────────────────────┐
 │                       Fifo  (16 × 32 dual-port memory)                   │
 │             synchronous write on wclk, combinational read                │
 └──────────────────────────────────────────────────────────────────────────┘
```
<img width="1562" height="676" alt="image" src="https://github.com/user-attachments/assets/6e451136-62a9-4a08-b927-f45208857878" />


## Module Descriptions

| Module | File | Responsibility |
|---|---|---|
| `cdc_top` | `rtl/cdc_top.sv` | Top level. Connects the write side, read side and memory. |
| `write_p` | `rtl/write_p.sv` | Write pointer (binary + Gray), `full` flag, read-pointer synchronizer, write handshake. |
| `Read_p` | `rtl/Read_p.sv` | Read pointer (binary + Gray), `empty` flag, write-pointer synchronizer, read handshake. |
| `Fifo` | `rtl/Fifo.sv` | 16 × 32 storage. Written on `wclk`, read combinationally by the read pointer. |

## Top-Level Interface

| Signal | Dir | Width | Domain | Description |
|---|---|---|---|---|
| `wclk` | in | 1 | write | Write clock |
| `rclk` | in | 1 | read | Read clock |
| `reset` | in | 1 | both | Active-low reset, sampled synchronously in each domain |
| `data_in_w` | in | 32 | write | Write data |
| `data_in_valid` | in | 1 | write | Write data is valid |
| `data_in_ready` | out | 1 | write | FIFO can accept data (`~full`) |
| `data_out_r` | out | 32 | read | Read data |
| `data_out_valid` | out | 1 | read | Read data is valid (FIFO not empty) |
| `data_out_ready` | in | 1 | read | Consumer accepts the data |

A transfer happens on a clock edge where `valid && ready` is high on that side.

## How the CDC Works

1. **Binary pointers** count writes and reads. The extra (fifth) bit distinguishes "full" from "empty" when the address bits are equal.
2. **Gray conversion** (`g = b ^ (b >> 1)`) is done from the *next* binary value and **registered** before the pointer leaves its domain. Nothing combinational sits between a source flop and the first synchronizer flop.
3. **Synchronizers**: each Gray pointer crosses through three back-to-back flops in the destination clock domain.
4. **Empty flag** (read domain): the next read Gray pointer is compared with the synchronized write Gray pointer.
5. **Full flag** (write domain): the next write Gray pointer is compared with the synchronized read Gray pointer **with the top two bits inverted**, which is the Gray-code form of "write pointer is exactly one lap ahead".
6. Both flags are **registered** and built from the next pointer value, so they describe the correct state in the cycle they are used.
7. Synchronized pointers lag the real ones, so the flags are **conservative**: `full` can stay asserted for a few cycles after the reader has freed a slot, and `empty` can stay asserted for a few cycles after data has been written. Neither flag ever claims space or data that is not there.

## Verification Environment

The testbench follows the standard layered structure and lives in one file (`tb/cdc_tb.sv`):

| Component | Role |
|---|---|
| `cdc_if` | Interface with separate clocking blocks for the write driver, read driver and both monitors |
| `transaction` | Random data word plus a random idle gap |
| `generator` | Produces transactions; `gap_max` controls writer idle time |
| `driver` | Drives the write side (holds valid until the monitor reports acceptance) and toggles read-side `ready` with a configurable probability |
| `monitor` | Observes both interfaces and reports every accepted write and every accepted read |
| `scoreboard` | In-order data check between accepted writes and accepted reads |
| `environment` | Builds and connects the components, runs reset, runs the test, and reports |
| `test` | Directed phases (below) |

**Test phases**

1. **Fill**: reader stalled, writer sends back-to-back. Checks that exactly **16** words are accepted, that `data_in_ready` then goes low, and that nothing was read.
2. **Drain**: reader enabled at 100 %. The words held back during the fill are written and all 30 words are read out in order.
3. **Random**: 200 words with random writer gaps (0–3 cycles) and the reader ready 50 % of the time.

**Assertions (SVA)**

- Write Gray pointer changes by at most one bit per `wclk`
- Read Gray pointer changes by at most one bit per `rclk`

**Pass criteria** (checked in `report()`): no scoreboard errors, nothing left pending, number of accepted writes equals accepted reads, and equals the number of words generated.

## Results

Vivado XSim 2025.2, `wclk` = 10 ns, `rclk` = 13 ns:

```
[575000]  fill done: wr=16 rd=0
[1229000] drain done: wr=30 rd=30
[1229000] random queued
[7079000] post_test done
sent=230 writes=230 reads=230 compared=230 errors=0 pending=0
PASS
```

All 230 words are transferred in order with no data errors, and no assertion fires.

## Running the Simulation

**Vivado (XSim)**

1. Create a project and add `rtl/*.sv` as design sources and `tb/cdc_tb.sv` as a simulation source.
2. Set `cdc_tb` as the simulation top.
3. Run the behavioral simulation to completion (`run all`). The testbench ends itself with `$finish`; a watchdog prints `TIMEOUT` after 90 µs if it hangs.
4. Look for the final `PASS` line in the Tcl console.

Tuning knobs in the `test` class: `env.drv.r_enable`, `env.drv.r_ready_pct`, `env.gen.gap_max`, and `env.gen.run(n)`.

## Repository Structure

```
.
├── rtl/
│   ├── cdc_top.sv
│   ├── Fifo.sv
│   ├── Read_p.sv
│   └── write_p.sv
├── tb/
│   └── cdc_tb.sv
└── README.md
```

## Known Limitations

This is a simulation-verified design. It has **not** been through formal CDC sign-off. Open items:

- No static CDC analysis or timing constraints yet (no `report_cdc` run, no `set_max_delay -datapath_only` / bus-skew constraints on the pointers)
- A single `reset` input feeds both clock domains; reset-domain crossing is not analyzed, and there is no per-domain reset synchronizer
- Synchronizer flops are not yet marked `ASYNC_REG`
- Simulation cannot show metastability; no randomized synchronizer-delay model is included
- Testbench covers one clock pair (10 ns / 13 ns); no clock-ratio sweep, no multi-seed regression, no reset in the middle of traffic, no functional coverage
- The `p_no_write_when_full` property in the testbench cannot fail (ready is defined as `~full`), so it is not counted as evidence; a pointer-based overflow/underflow assertion is still to be written
- The memory is read combinationally, so it maps to distributed (LUT) RAM on FPGAs, not block RAM
- Some redundant conditions remain in the pointer-increment and valid logic

## Roadmap

- [ ] Replace the vacuous assertion with real overflow and underflow checks
- [ ] Add a functional covergroup (full, empty, simultaneous push/pop, pointer wraparound)
- [ ] Sweep clock ratios and random seeds; test reset during traffic
- [ ] Add a randomized 0/1-cycle synchronizer-delay model to the testbench
- [ ] Per-domain reset synchronizers and `ASYNC_REG` attributes
- [ ] Vivado `report_cdc` run with proper CDC constraints
- [ ] Formal proof of the FIFO invariants with SymbiYosys
- [ ] MTBF calculation for the chosen synchronizer depth
- [ ] Port the testbench to UVM

## Author

**Joydeb Sarkar**
Electronics and Communication Engineering, IIT Patna
Focus: RTL design and digital verification
