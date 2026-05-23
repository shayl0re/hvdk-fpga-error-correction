# Setup Guide: HVDK Error Correction on Dual Basys3 FPGAs

This guide walks you through every step to get your dual-FPGA error correction system up and running.

---

## Prerequisites

- **Hardware**:
  - 2× Basys3 FPGA boards
  - 1× 8×8 LED matrix (Max7219 module)
  - Jumper wires (at least 3: TX, RX, GND)
  - 2× USB cables (for programming & power)
  - 2× Laptops/PCs

- **Software**:
  - Vivado 2022.1+ (or your preferred version matching Basys3 compatibility)
  - PuTTY (serial terminal emulator)
  - Git (optional, for cloning this repository)

---

## Part 1: Hardware Setup

### Step 1.1: Physical Assembly

#### Board Placement
1. Place both Basys3 boards on a flat, static-safe surface
2. Position them so the PMOD connectors face each other (easier for wiring)
3. Leave ~10cm between boards for ventilation

#### Jumper Wire Connections
The UART communication uses PMOD JA (the 8-pin header on the right side of each board).

```
FPGA1 PMOD JA Pin Diagram:        FPGA2 PMOD JA Pin Diagram:
┌─ 1 (J1)  - TX to FPGA2 RX     ┌─ 1 (J1)  - RX from FPGA1 TX
├─ 2 (K1)  - GND                ├─ 2 (K1)  - GND
├─ 3 (J2)  - (unused)           ├─ 3 (J2)  - (unused)
├─ 4 (K2)  - (unused)           ├─ 4 (K2)  - (unused)
├─ 5 (H5)  - (unused)           ├─ 5 (H5)  - (unused)
├─ 6 (J5)  - (unused)           ├─ 6 (J5)  - (unused)
├─ 7 (H4)  - (unused)           ├─ 7 (H4)  - (unused)
└─ 8 (J4)  - (unused)           └─ 8 (J4)  - (unused)
```

**Wiring Steps**:
1. Take one jumper wire and connect:
   - FPGA1 PMOD JA **pin 1 (J1)** → FPGA2 PMOD JA **pin 1 (J1)**
   - *(This is the UART TX/RX line; the hardware handles direction)*

2. Take a second jumper wire and connect:
   - FPGA1 PMOD JA **pin 2 (K1)** → FPGA2 PMOD JA **pin 2 (K1)**
   - *(This is the GND/return line)*

3. Double-check all connections are **firmly seated** in the PMOD connector

#### Max7219 LED Matrix Connections (to FPGA2)
The 8×8 LED matrix connects to FPGA2 via SPI or I2C (pins specified in `max7219_hvdk.v`).

Typical wiring (verify in your module):
- **VCC** → 5V (Basys3 PMOD power)
- **GND** → PMOD GND
- **DIN** → FPGA2 SPI MOSI (PMOD JB pin 1)
- **CLK** → FPGA2 SPI SCK (PMOD JB pin 3)
- **CS** → FPGA2 SPI CS (PMOD JB pin 4)

> **Check your `max7219_hvdk.v` file** for the exact pin mapping!

#### Power & Programming Cables
1. Connect **USB cable #1** from Laptop1 to FPGA1 board (USB PROG port)
2. Connect **USB cable #2** from Laptop2 to FPGA2 board (USB PROG port)
3. Both boards will power on once connected

---

## Part 2: Vivado Project Setup

### Step 2.1: Open Vivado on Laptop1 (FPGA1)

1. Launch Vivado
2. Click **Create Project**
3. Choose project name (e.g., `FPGA1_HVDK`) and location
4. Select **RTL Project** → Next
5. **Add Design Sources**:
   - Click **Add Files** or **Add Directories**
   - Navigate to the repo: `fpga1/verilog/`
   - Select all `.v` files:
     - `top_fpga1.v`
     - `uart_rx.v`
     - `uart_tx.v`
     - `max7219_hvdk.v`
   - Click **Finish**

6. **Add Constraints**:
   - Click **Add Constraint Files**
   - Navigate to `fpga1/constraints/`
   - Select `fpga1.xdc`
   - Click **Finish**

7. In the **Hierarchy** pane on the left, right-click `top_fpga1.v` and select **Set as Top**

8. Click **Run Synthesis** (⚡ icon)
   - Wait for synthesis to complete (~2-5 minutes)
   - Check for any errors in the **Messages** tab

9. Click **Run Implementation**
   - Wait for implementation (~3-10 minutes)

10. Click **Generate Bitstream**
    - This produces the `.bit` file for programming

### Step 2.2: Program FPGA1

1. In Vivado, go to **Flow** → **Open Hardware Manager**
2. Click **Open Target** → **Auto Connect**
   - Vivado should detect your Basys3 board
3. Right-click the board in the **Hardware** pane and select **Program Device**
4. A dialog appears. Click **Program** to load the bitstream
5. Wait for the message: **"Programming completed successfully"**

**FPGA1 is now programmed!** The board will show the loaded configuration.

---

### Step 2.3: Open Vivado on Laptop2 (FPGA2)

Repeat **Steps 2.1-2.2** but for FPGA2:
- Use `fpga2/verilog/` and `fpga2/constraints/fpga2.xdc`
- Set `top_fpga2.v` as the Top module
- Generate bitstream and program the FPGA2 board

---

## Part 3: PuTTY Configuration (Laptop2)

PuTTY is your terminal to see the corrected data output from FPGA2.

### Step 3.1: Identify the COM Port

**On Windows**:
1. Plug in the USB cable for FPGA2
2. Open **Device Manager** (right-click Start → Device Manager)
3. Expand **Ports (COM & LPT)**
4. Look for a new entry like **"USB Serial Port (COM3)"** or similar
5. **Note the COM number** (e.g., COM3)

**On Linux**:
1. Open a terminal
2. Run: `dmesg | grep tty` or `ls /dev/tty*`
3. Look for entries like `/dev/ttyUSB0` or `/dev/ttyACM0`
4. **Note the device path**

**On macOS**:
1. Open Terminal
2. Run: `ls /dev/cu.*`
3. Look for entries like `/dev/cu.usbserial-*`
4. **Note the device path**

### Step 3.2: Configure PuTTY

1. **Launch PuTTY**

2. **Session**:
   - **Connection type**: Select **Serial**
   - **Serial line**: Enter the COM port you identified (e.g., `COM3` on Windows, `/dev/ttyUSB0` on Linux)
   - **Speed**: `9600` (must match FPGA2 baud rate)

3. **Serial** (in left sidebar):
   - **Speed (baud rate)**: `9600`
   - **Data bits**: `8`
   - **Stop bits**: `1`
   - **Parity**: `None`
   - **Flow control**: `None`

4. **Optional - Terminal** (in left sidebar):
   - **Local echo**: `Force on` (so you see what you type)
   - **Local line editing**: `Force on`

5. **Save the session**:
   - Go back to **Session**
   - In the **Saved Sessions** field, type a name (e.g., `FPGA2_HVDK`)
   - Click **Save**

6. Click **Open** to connect

You should see a blank terminal window. This is normal—it means you're connected and waiting for data from FPGA2.

---

## Part 4: Running the System

### Step 4.1: Reset Both Boards

1. Press the **reset button** (BTNC) on **FPGA1**
   - You should see something on the LEDs or no visible change (depends on your design)
2. Press the **reset button** (BTNC) on **FPGA2**
   - LEDs should light up briefly

### Step 4.2: Send Input Data from Vivado (FPGA1)

In your Vivado design, you have two ways to input 8-bit data:

**Option A: DIP Switches** (if `top_fpga1.v` includes them)
1. Set the 8 DIP switches on FPGA1 to your desired bit pattern
   - E.g., `10101100` means: SW7=1, SW6=0, SW5=1, SW4=0, SW3=1, SW2=1, SW1=0, SW0=0
2. Press a button (e.g., BTNA) to trigger transmission

**Option B: Hardcoded Values** (simplest for testing)
1. Edit `top_fpga1.v` in Vivado
2. Find the line where data is sent (look for `uart_tx` module call)
3. Replace with a fixed value: `data_to_send <= 8'b10101100;` (example)
4. Re-synthesize, implement, and program

### Step 4.3: Observe the System in Action

**On FPGA2 (Hardware)**:
1. **LEDs LD0-LD7** show the current byte:
   - Corrupted byte (2 seconds): Random single bit flipped
   - Corrected byte (2 seconds): Back to original
2. **LEDs LD8-LD13** show parity bits P0-P5
3. **8×8 LED Matrix**: Visualizes the HVDK 8×8 grid with correction highlighting

**In PuTTY Terminal (Laptop2)**:
1. After FPGA2 corrects the byte, you'll see output like:
   ```
   10101100
   ```
   (This is the corrected 8-bit value + newline)

2. The next cycle begins immediately

### Step 4.4: Test Different Input Values

1. Change the DIP switches (or hardcoded value) on FPGA1
2. Press the trigger button (or let it auto-loop)
3. Watch FPGA2 LEDs and PuTTY output
4. Verify the output matches your input

**Example Test Cases**:
- All zeros: `00000000`
- All ones: `11111111`
- Alternating: `10101010`
- Single bit: `00000001`, `00000010`, `00000100`, etc.

---

## Part 5: Interpreting Results

### LED Display Meaning

**LD0-LD7** (Data byte):
- Initially shows **corrupted byte** (one random bit flipped) — Red/dim
- After 2 seconds shows **corrected byte** (back to original) — Green/bright

**LD8-LD13** (Parity bits P0-P5):
- Parity bits calculated from current byte
- Used for error detection & correction internally

**8×8 Matrix**:
- Each cell represents one bit in the 8×8 HVDK grid
- Shows which bit was corrupted and corrected
- Pattern updates in real-time

### PuTTY Output Interpretation

Each line is the **corrected 8-bit value as a binary string**:
```
10101100   ← Bit 7 = 1, Bit 6 = 0, Bit 5 = 1, etc.
11001010   ← Next input
00110011   ← Next input
```

---

## Troubleshooting

### Issue: No data in PuTTY

**Causes**:
1. Wrong COM port selected
2. Baud rate mismatch (9600 required)
3. FPGA2 not programmed correctly
4. USB cable loose or damaged

**Solutions**:
- Verify COM port in Device Manager/Terminal
- Check baud rate is exactly 9600 in PuTTY and FPGA2 code
- Re-program FPGA2 bitstream
- Try different USB cable or port

### Issue: LEDs not lighting

**Causes**:
1. FPGA2 bitstream not programmed
2. Pin assignments wrong in `fpga2.xdc`
3. Power supply issue

**Solutions**:
- Check programming messages in Vivado Hardware Manager
- Verify pin numbers in `.xdc` file match your board (check Basys3 datasheet)
- Ensure USB power supply provides enough current (may need external power)

### Issue: UART Communication Failing

**Causes**:
1. Jumper wires not fully inserted
2. Wrong pins in PMOD JA
3. Baud rate divisor calculation wrong
4. Clock frequency not 100 MHz

**Solutions**:
- Reseat all PMOD JA jumper wires firmly
- Double-check pins J1 and K1 on both boards
- Verify `BAUD_DIV = CLK_HZ / BAUD_RATE` calculation
- Confirm 100 MHz oscillator on Basys3 (should be default)

### Issue: Random errors or data corruption

**Causes**:
1. Noisy jumper wire connections
2. Crossed TX/RX lines (should be pin-to-pin, not crossed)
3. Ground not properly connected

**Solutions**:
- Use shielded jumper wires if available
- Verify TX→RX and RX→TX direction (pin 1 FPGA1 → pin 1 FPGA2)
- Add additional GND jumpers for better grounding

---

## Advanced Customization

### Changing Baud Rate

Edit both FPGA modules:
- `fpga1/verilog/top_fpga1.v` → `localparam BAUD_RATE = 115200;`
- `fpga2/verilog/top_fpga2.v` → `localparam BAUD_RATE = 115200;`
- Update PuTTY Serial → Speed to match

### Changing Error Injection Delay

Edit `fpga2/verilog/top_fpga2.v`:
```verilog
localparam DELAY_2S = 200_000_000;  // 2 seconds at 100 MHz
```

Change `200_000_000` to your desired value:
- 1 second: `100_000_000`
- 5 seconds: `500_000_000`

### Disabling Error Injection (Test Correctness)

Comment out the bit flip in `top_fpga2.v`:
```verilog
// corrupt_data <= orig_data ^ (8'd1 << flip_pos);  // DISABLE
corrupt_data <= orig_data;  // Always show original
```

---

## Next Steps

1. **Explore the Code**: Read through the Verilog modules to understand the HVDK encoding/decoding
2. **Modify Parameters**: Try different baud rates, delays, and test vectors
3. **Extended Functionality**: Add multi-byte error correction, CRC checks, or different parity schemes
4. **Documentation**: Document your setup and add photos to the `images/` folder

---

## Additional Resources

- [Basys3 Reference Manual](https://digilent.com/reference/programmable-logic/basys-3/start?srsltid=AfmBOop-zZvZBx5p1fqT9zSZTAkQu77bEuwMFsUZVzopc3T2VM_3HNYd)
- [PuTTY Documentation](https://www.chiark.greenend.org.uk/~sgtatham/putty/docs.html)
- [Vivado User Guide](https://docs.xilinx.com/r/en-US/ug910-vivado-getting-started/)

---

**Happy debugging!** If you encounter issues, check the `TROUBLESHOOTING.md` file or open a GitHub issue.
