# Analytical Combinator

A [Factorio](https://www.factorio.com) mod adding a programmable circuit combinator
controlled via a RISC-V inspired assembly language.

Inspired and derived from joalon's [Assembly Combinator](https://mods.factorio.com/mod/assembly-combinator), but heavily modified to include read signal capability.

All development was done by Anthropic's Claude AI.

## Usage

Download it from the [mod portal](https://mods.factorio.com/mod/analytical-combinator).

The analytical combinator is based on a **Decider Combinator** and supports both
input (red and green wires) and output circuit network connections.

## Instruction set

### Arithmetic

| Instruction | Syntax | Description |
|-------------|--------|-------------|
| `ADDI` | `rd, rs, imm` | `rd = rs + imm` — add immediate constant |
| `ADD`  | `rd, rs, rt`  | `rd = rs + rt`  — add two registers |
| `SUB`  | `rd, rs, rt`  | `rd = rs - rt`  — subtract register |

### Comparison

| Instruction | Syntax | Description |
|-------------|--------|-------------|
| `SLT`  | `rd, rs, rt`  | `rd = (rs < rt) ? 1 : 0` |
| `SLTI` | `rd, rs, imm` | `rd = (rs < imm) ? 1 : 0` |

### Control flow

| Instruction | Syntax | Description |
|-------------|--------|-------------|
| `JAL` | `rd, label` | Jump to label; save return address in rd (use x0 to discard) |
| `BEQ` | `rs, rt, label` | Branch to label if rs == rt |
| `BNE` | `rs, rt, label` | Branch to label if rs != rt |

### Circuit network output

| Instruction | Syntax | Description |
|-------------|--------|-------------|
| `WSIG` | `od, signal, rs` | Write signal to output channel od (o0–o3) with count from rs |

### Circuit network input

| Instruction | Syntax | Description |
|-------------|--------|-------------|
| `RSIGR` | `rd, signal` | Read named signal from the **red** input wire into rd (0 if absent) |
| `RSIGG` | `rd, signal` | Read named signal from the **green** input wire into rd (0 if absent) |

### Control

| Instruction | Syntax | Description |
|-------------|--------|-------------|
| `WAIT` | `imm` or `rs` | Stall for N game ticks (60 ticks = 1 second) |
| `NOP`  | — | No operation |
| `HLT`  | — | Halt execution |

### Registers

- `x0`–`x31`: general-purpose integer registers. `x0` is always 0 (writes ignored).
- `o0`–`o3`: output signal registers, written by `WSIG`, emitted on the output network each tick.

## Example programs

### Simple counter (output only)

```
main:
    ADDI x10, x0, 0             # Initialize counter to 0
loop:
    ADDI x10, x10, 1            # Increment counter
    WSIG o1, copper-plate, x10  # Output counter value
    WAIT 60                     # Wait 1 second (60 game ticks)
    SLTI x6, x10, 100           # Check if counter < 100
    BNE  x6, x0, loop           # Branch if not equal to zero
    JAL  x1, main               # Jump back to main
```

### Threshold gate (read input, control output)

Reads an iron-ore count from the green wire. Once it exceeds 500,
outputs signal-A = 1 on the output connector and halts. The signal
appears on whichever wire(s) — red, green, or both — are physically
connected to the output side of the combinator.

```
poll:
    RSIGG x10, iron-ore         # Read iron-ore from green wire
    SLTI  x6, x10, 500          # x6 = 1 if count < 500
    BNE   x6, x0, poll          # Keep polling until threshold met
    ADDI  x11, x0, 1
    WSIG  o0, signal-A, x11     # Emit signal-A = 1
    HLT
```

### Red/green signal sum

Reads a signal from both wires each tick and outputs their sum. Useful
when two separate parts of a factory each report a count on different
wire colours and you want a combined total.

```
loop:
    RSIGR x10, iron-plate       # Read iron-plate from red wire
    RSIGG x11, iron-plate       # Read iron-plate from green wire
    ADD   x12, x10, x11         # x12 = red + green total
    WSIG  o0, iron-plate, x12   # Output the combined count
    WAIT  1
    JAL   x0, loop
```

### Red/green sum with threshold gate

Same idea, but halts and fires a signal once the combined total exceeds 500.

```
loop:
    RSIGR x10, iron-plate       # Read iron-plate from red wire
    RSIGG x11, iron-plate       # Read iron-plate from green wire
    ADD   x12, x10, x11         # x12 = red + green total
    SLTI  x6,  x12, 500         # x6 = 1 if total < 500
    BNE   x6,  x0,  loop        # Keep polling until threshold met
    ADDI  x11, x0,  1
    WSIG  o0,  signal-A, x11    # Emit signal-A = 1
    HLT
```

