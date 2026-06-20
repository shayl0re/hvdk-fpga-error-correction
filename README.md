# HVDK Parity-Based Error Correction on Dual Basys3 FPGAs

A complete hardware implementation of **HVDK (Horizontal-Vertical-Diagonal-Knight) parity-based single-bit error detection and correction** using two Basys3 FPGA boards connected via UART wired communication.

## Overview

This project demonstrates real-time error injection and correction across a multi-component wireless hardware chain:

- **FPGA1 (Basys3)**: Receives 8-bit binary input from Vivado → Encodes with HVDK parity → Sends via UART to FPGA2
- **FPGA2 (Basys3)**: Receives byte from FPGA1 → Injects random single-bit error → Displays corrupted byte on LEDs → After 2-second delay, corrects the error → Displays corrected byte on LEDs & 8×8 Max7219 LED matrix → Sends binary output to PuTTY

**Error Correction Visualization**: The 8×8 LED matrix displays the HVDK parity grid in real-time, showing before/after correction.

---

## Hardware Requirements

| Component | Quantity | Details |
|-----------|----------|---------|
| **Basys3 FPGA Board** | 2 | Xilinx Artix-7, xc7a35tcpg236-1 |
| **8×8 LED Matrix (Max7219)** | 1 | Connected to FPGA2 for visualization |
| **Jumper Wires** | ~8 | UART TX/RX lines between FPGAs |
| **USB Cable** | 2 | For programming & power (one per board) |
| **PC/Laptop** | 2 | Laptop1: Vivado (FPGA1 control), Laptop2: PuTTY (FPGA2 monitoring) |

### Reference
- [Basys3 Reference Manual](https://digilent.com/reference/programmable-logic/basys-3/start?srsltid=AfmBOop-zZvZBx5p1fqT9zSZTAkQu77bEuwMFsUZVzopc3T2VM_3HNYd)

---

## Pin Configuration

### FPGA1 (Basys3) - `fpga1/constraints/fpga1.xdc`

| Signal | Pin | Purpose |
|--------|-----|---------|
| `clk` | W5 | 100 MHz system clock |
| `rst_btn` | U18 | Reset button (active HIGH) |
| `tx_to_fpga2` | J1 | UART TX to FPGA2 (PMOD JA pin 1) |
| `led[15:0]` | Various | Status LEDs (optional debug) |

### FPGA2 (Basys3) - `fpga2/constraints/fpga2.xdc`

| Signal | Pin | Purpose |
|--------|-----|---------|
| `clk` | W5 | 100 MHz system clock |
| `rst_btn` | U18 | Reset button (active HIGH) |
| `fpga1_rx` | J1 | UART RX from FPGA1 (PMOD JA pin 1) |
| `pc_tx` | A18 | USB-UART TX to PC2 (PuTTY) |
| `led[7:0]` | U16, E19, U19, V19, W18, U15, U14, V14 | Data bits display (corrupted → corrected) |
| `led[13:8]` | V13, V3, W3, U3, P3, N3 | Parity bits P0-P5 display |

### Jumper Wire Connections

```
FPGA1 PMOD JA pin 1 (TX) ----[jumper wire]---- FPGA2 PMOD JA pin 1 (RX)
FPGA1 GND ----[jumper wire]---- FPGA2 GND
```

---

## System Architecture

```
┌─────────────┐         UART (9600 baud)         ┌─────────────┐
│   Vivado    │──────────────────────────────────▶│   FPGA1     │
│  (Laptop1)  │                                   │  (Basys3)   │
└─────────────┘                                   └──────┬──────┘
                                                         │
                                    PMOD JA jumper wire  │
                                                         │
                                                   ┌─────▼──────┐
                                                   │   FPGA2    │
                                                   │ (Basys3)   │
                                                   └──┬────┬────┘
                                                      │    │
                                         USB-UART    │    │  SPI/I2C
                                                      │    │
                                          ┌──────────▼─┐  │
                                          │   PuTTY    │  │
                                          │  (Laptop2) │  │
                                          └────────────┘  │
                                                      ┌───▼────────┐
                                                      │ Max7219    │
                                                      │ 8×8 Matrix │
                                                      └────────────┘
```

---

## Project Workflow

### 1. **Input (FPGA1 via Vivado)**
   - User provides 8-bit binary input (e.g., `10101100`)
   - FPGA1 encodes byte using HVDK parity (64 data bits → 96-bit frame)
   - UART TX sends frame to FPGA2 at 9600 baud

### 2. **Error Injection (FPGA2)**
   - Receives byte from FPGA1
   - Free-running LFSR selects random bit position (0-7)
   - **One bit is flipped** (simulating transmission noise)
   - Corrupted byte displayed on `led[7:0]` (red = error)
   - Parity bits displayed on `led[13:8]`
   - **2-second delay** for visual observation

### 3. **Error Correction (FPGA2)**
   - Calculates HVDK syndromes (P0-P5)
   - Identifies error location via row & column parity intersection
   - **Corrects the flipped bit** back to original
   - Corrected byte displayed on `led[7:0]` (green = correct)
   - **8×8 LED matrix visualizes the HVDK grid** showing correction

### 4. **Output (FPGA2 via PuTTY)**
   - Sends corrected 8-bit binary string as ASCII (`XXXXXXXX\r\n`)
   - Example: `10101100\r\n` → displayed in PuTTY terminal
   - Ready for next input

---

## HVDK Parity Method

The HVDK method encodes 64 data bits as an 8×8 grid and computes parity across four independent dimensions:

- **P0**: Horizontal parity (all even rows)
- **P1**: Vertical parity (all even columns)
- **P2**: Diagonal parity (main diagonal + wrapping)
- **P3**: Anti-diagonal parity
- **P4**: Knight-move parity (chess knight pattern)
- **P5**: Overall parity (XOR of all bits)

**Error Correction**: Syndrome calculation identifies the exact bit position, enabling single-bit correction.

**Files**:
- `fpga1/verilog/hvdk_encoder.v` – Encodes 64→96 bits
- `fpga2/verilog/hvdk_decoder.v` – Decodes & corrects
- `fpga2/verilog/max7219_hvdk.v` – LED matrix visualization

---

## Setup Instructions

### Step 1: Hardware Assembly
1. Place two Basys3 boards side-by-side
2. Connect FPGA1 & FPGA2 via jumper wires:
   - FPGA1 PMOD JA pin 1 (J1) → FPGA2 PMOD JA pin 1 (J1)
   - FPGA1 GND → FPGA2 GND
3. Connect Max7219 8×8 matrix to FPGA2 (SPI/I2C as per max7219_hvdk.v)
4. USB power both boards from separate laptops

### Step 2: Load Bitstreams (Vivado)

**FPGA1**:
1. Open Vivado → Create new project
2. Add files from `fpga1/verilog/` and `fpga1/constraints/fpga1.xdc`
3. Synthesize, implement, generate bitstream
4. Program Basys3 board

**FPGA2**:
1. Open Vivado → Create new project
2. Add files from `fpga2/verilog/` and `fpga2/constraints/fpga2.xdc`
3. Synthesize, implement, generate bitstream
4. Program Basys3 board

### Step 3: Configure PuTTY (Laptop2)

1. **Open PuTTY**
2. **Session**:
   - Host Name: (leave blank if using COM port)
   - Connection type: **Serial**
   - Serial line: `COM3` (or appropriate port for your FPGA2)
3. **Serial**:
   - Speed (baud): **9600**
   - Data bits: **8**
   - Stop bits: **1**
   - Parity: **None**
   - Flow control: **None**
4. Click **Open**

### Step 4: Run Test

1. Reset FPGA1 by pressing the reset button
2. **LED Display on FPGA2**:
   - `led[7:0]` shows current byte (corrupted for 2 seconds, then corrected)
   - `led[13:8]` shows parity bits
   - **8×8 Matrix** visualizes the HVDK correction grid in real-time
3. **PuTTY Output**:
   - Shows binary string of corrected byte + newline
   - Example: `10101100\r\n`
4. Each cycle takes ~2 seconds (1s corrupt display + 1s buffer)

---

## Project Structure

```
hvdk-fpga-error-correction/
├── fpga1/
│   ├── verilog/
│   │   ├── top_fpga1.v          # Top-level design (main control)
│   │   ├── uart_rx.v            # UART receiver (9600 baud)
│   │   ├── uart_tx.v            # UART transmitter (9600 baud)
│   │   └── max7219_hvdk.v       # Max7219 LED matrix driver
│   └── constraints/
│       └── fpga1.xdc            # Pin configuration
├── fpga2/
│   ├── verilog/
│   │   ├── top_fpga2.v          # Top-level design (error injection & correction)
│   │   ├── uart_rx2.v           # UART receiver (9600 baud)
│   │   ├── uart_tx2.v           # UART transmitter (9600 baud)
│   │   └── hvdk_decoder.v       # HVDK parity decoder & error corrector
│   └── constraints/
│       └── fpga2.xdc            # Pin configuration
├── docs/
│   ├── HVDK_THEORY.md           # Mathematical details of HVDK method
│   ├── SETUP_GUIDE.md           # Detailed setup instructions
│   └── TROUBLESHOOTING.md       # Common issues & solutions
├── images/
│   ├── block_diagram.svg        # System architecture diagram
│   ├── hardware_setup.jpg       # Photo of assembled system (optional)
│   └── led_matrix_output.jpg    # Example LED matrix display (optional)
├── README.md                    # This file
├── .gitignore                   # Git ignore for Vivado artifacts
└── CHANGELOG.md                 # Version history
```

---

## Customizable Parameters

Users can modify these values in the top-level modules:

### FPGA1 (`fpga1/verilog/top_fpga1.v`)
- **`CLK_HZ`**: System clock frequency (default: 100 MHz)
- **`BAUD_RATE`**: UART baud rate (default: 9600)
- **`BAUD_DIV`**: Baud rate divisor (auto-calculated)

### FPGA2 (`fpga2/verilog/top_fpga2.v`)
- **`CLK_HZ`**: System clock frequency (default: 100 MHz)
- **`BAUD_RATE`**: UART baud rate (default: 9600)
- **`DELAY_2S`**: Delay before correction display (default: 200M cycles = 2 seconds)
- **LFSR seed**: `lfsr <= 8'hAC` → change to any non-zero value for different random patterns

### Max7219 LED Matrix (`fpga2/verilog/max7219_hvdk.v`)
- **Multiplexing frequency**: ~800 Hz (adjustable via counter)
- **Brightness**: SPI command in max7219_hvdk.v

---

## Testing & Validation

### Manual Test Case
1. Input byte: `10101100` (0xAC)
2. FPGA1 encodes → sends to FPGA2
3. FPGA2 injects error at random bit (e.g., bit 3) → `10101000` (0xA8)
4. LEDs show corrupted byte for 2 seconds
5. HVDK correction identifies bit 3, flips it back → `10101100`
6. LEDs show corrected byte
7. PuTTY displays: `10101100\r\n`

### Automated Testing
Run bitstreams in simulation mode (Vivado Behavioral Simulation) with various test vectors:
- All zeros: `00000000`
- All ones: `11111111`
- Alternating: `10101010`
- Single bit set: `00000001`, `00000010`, etc.

---

## Troubleshooting

### No data appearing in PuTTY
- Check COM port is correct (Device Manager → Ports)
- Verify FPGA2 USB cable is properly connected
- Confirm baud rate is 9600 in PuTTY settings
- Reset FPGA2 with button

### LEDs not lighting up
- Check pin assignments in fpga2.xdc match actual LED locations
- Verify bitstream loaded successfully (Vivado → Program Device)
- Test with simpler code (e.g., all LEDs ON)

### 8×8 Matrix not displaying
- Verify SPI/I2C connections to Max7219
- Check max7219_hvdk.v SPI timing matches module spec
- Ensure Max7219 power supply is stable

### UART communication failing
- Confirm jumper wire connections between PMOD JA pins
- Check for shorts or loose connections
- Test UART with loopback on each FPGA individually
- Verify baud rate divisor calculation

See **`docs/TROUBLESHOOTING.md`** for detailed debugging steps.

---

## References

- **Basys3 Board**: [Digilent Reference](https://digilent.com/reference/programmable-logic/basys-3/start?srsltid=AfmBOop-zZvZBx5p1fqT9zSZTAkQu77bEuwMFsUZVzopc3T2VM_3HNYd)
- **HVDK Parity Method**: Classical error correction technique (extensions of Hamming codes)
- **Max7219 LED Driver**: [Datasheetby Maxim Integrated](https://datasheets.maximintegrated.com/en/ds/MAX7219.pdf)

---

## Changelog

### v1.0 (Initial Release)
- Complete dual-FPGA HVDK error correction system
- UART communication between boards
- 8×8 LED matrix visualization
- Real-time error injection & correction demonstration
- PuTTY terminal interface

---


For questions or issues, open a GitHub issue.

---

**Happy error correcting!** 🎉
