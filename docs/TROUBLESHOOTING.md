# Troubleshooting Guide

Comprehensive debugging tips for common issues with the HVDK error correction system.

---

## Communication Issues

### Problem: PuTTY Shows No Data / Blank Terminal

**Symptom**: PuTTY connects but displays nothing, or shows garbage characters.

**Checklist**:
- [ ] FPGA2 is programmed with correct bitstream
- [ ] USB cable for FPGA2 is firmly connected
- [ ] COM port in PuTTY matches Device Manager
- [ ] Baud rate is set to **9600** (not 115200, 19200, etc.)
- [ ] Data bits = 8, Stop bits = 1, Parity = None, Flow control = None

**Diagnostic Steps**:

1. **Verify COM Port**:
   ```bash
   # Windows: Open Device Manager, check Ports (COM & LPT)
   # Linux: ls /dev/ttyUSB*
   # macOS: ls /dev/cu.usbserial-*
   ```

2. **Check if FPGA2 is responding**:
   - Disconnect FPGA1 from FPGA2 (remove jumper wires)
   - Open PuTTY to FPGA2
   - Press reset button on FPGA2
   - You should see some activity or LED changes

3. **Test UART independently**:
   - Modify `top_fpga2.v` to send a constant byte every second:
     ```verilog
     // In the SEND state, hardcode:
     snd_data <= 8'b10101010;  // Send 0xAA repeatedly
     ```
   - Re-synthesize, implement, program
   - Watch PuTTY for repeated output

4. **Check cable integrity**:
   - Try a different USB cable
   - Try a different USB port on your laptop

**Solution**: If still not working, the UART RX/TX modules may have an issue. Review the `.xdc` file pin assignments against the Basys3 datasheet.

---

### Problem: Garbage Characters in PuTTY

**Symptom**: PuTTY shows random symbols like `äëï...` instead of binary digits.

**Causes**:
1. Baud rate mismatch
2. Hardware UART not initialized correctly
3. Clock frequency is not 100 MHz

**Fix**:
1. **Verify baud rate**:
   - PuTTY Serial → Speed should be `9600`
   - Check FPGA2 `top_fpga2.v`: `localparam BAUD_RATE = 9600;`
   - Calculate baud divisor: `BAUD_DIV = 100_000_000 / 9600 = 10416`

2. **Force re-sync**:
   - Close PuTTY
   - Reset FPGA2 button
   - Open PuTTY again

3. **If still garbled**, increase baud delay in UART module:
   ```verilog
   // In uart_tx2.v, increase counter width if needed:
   reg [14:0] cnt;  // was [13:0]
   ```

---

### Problem: FPGA1 → FPGA2 UART Connection Dead

**Symptom**: FPGA2 receives no data from FPGA1 (PuTTY stays blank).

**Checklist**:
- [ ] Jumper wires firmly seated in PMOD JA pin 1 on both boards
- [ ] GND wire connected between boards
- [ ] FPGA1 programmed correctly
- [ ] UART TX/RX pin assignments match `.xdc` files

**Diagnostic Steps**:

1. **Check jumper wire connections**:
   ```
   FPGA1 PMOD JA:           FPGA2 PMOD JA:
   Pin 1 (J1) ----wire---- Pin 1 (J1)
   Pin 2 (K1) ----wire---- Pin 2 (K1)
   ```
   Gently tug on each wire—it should not wiggle.

2. **Verify pin assignments**:
   - Open `fpga1/constraints/fpga1.xdc`
     - Find: `set_property -dict { PACKAGE_PIN J1 ...} [get_ports tx_to_fpga2]`
     - Should be **J1** (PMOD JA pin 1)
   
   - Open `fpga2/constraints/fpga2.xdc`
     - Find: `set_property -dict { PACKAGE_PIN J1 ...} [get_ports fpga1_rx]`
     - Should be **J1** (PMOD JA pin 1)

3. **Test FPGA1 output manually**:
   - Modify `top_fpga1.v` to send constant byte:
     ```verilog
     localparam DATA_OUT = 8'b10101010;
     ```
   - Re-program FPGA1
   - Monitor FPGA2 PuTTY output

4. **Measure voltage on jumper wire** (if you have a multimeter):
   - FPGA1 PMOD JA pin 1 should toggle between 0V and 3.3V
   - If stuck at 3.3V or 0V, FPGA1 TX may be dead

**Solution**: If UART still not working:
- Check if FPGA1 synthesis had errors (check Vivado Messages tab)
- Try a loopback test on FPGA1 alone (TX → RX same board)
- Check 100 MHz clock is stable (use Clock Wizard if issues persist)

---

## LED Display Issues

### Problem: LEDs Not Lighting Up

**Symptom**: All LEDs on FPGA2 remain OFF (no lights at all).

**Checklist**:
- [ ] FPGA2 programmed successfully (no errors in Vivado)
- [ ] Pin assignments in `fpga2.xdc` are correct
- [ ] Power supply is adequate (may need external 5V for LEDs)
- [ ] LED board itself is not faulty

**Diagnostic Steps**:

1. **Verify bitstream was programmed**:
   - Open Vivado Hardware Manager
   - Right-click FPGA2 board → Program Device
   - Check message window for: **"Programming completed successfully"**

2. **Test with simple design**:
   - Create a minimal test in `top_fpga2.v`:
     ```verilog
     assign led[7:0] = 8'b11111111;  // All ON
     ```
   - Re-synthesize, implement, program
   - All 8 LEDs should light up

3. **Check pin assignments**:
   - Open `fpga2.xdc`
   - Look for LED pin assignments (should be U16, E19, U19, etc.)
   - Cross-reference with [Basys3 schematic](https://digilent.com/reference/programmable-logic/basys-3/start)

4. **Measure voltage on LED pin**:
   - With design programmed, use multimeter on one LED pin
   - Should see voltage swing between 0-3.3V when toggling
   - If stuck, FPGA I/O may be damaged

**Solution**: If no luck:
- Try synthesizing a fresh project with just LED test
- Check FPGA power supply (VCCO voltage)
- Verify LVCMOS33 I/O standard in constraints

---

### Problem: LEDs Flash But Don't Show Correct Pattern

**Symptom**: LEDs light up but don't display the corrupted/corrected bytes properly.

**Likely Cause**: Logic error in data assignment or parity calculation.

**Debug Steps**:

1. **Check LED bit ordering**:
   - `led[0]` should be LD0, `led[1]` should be LD1, etc.
   - In Vivado Simulation, verify `disp_data` matches LED output

2. **Verify parity calculation**:
   - In `top_fpga2.v`, check the parity XOR operations:
     ```verilog
     wire dp0 = disp_data[0]^disp_data[1]^disp_data[2]^disp_data[3];  // P0
     wire dp1 = disp_data[4]^disp_data[5]^disp_data[6]^disp_data[7];  // P1
     ```

3. **Run Behavioral Simulation**:
   - In Vivado: **Simulation → Run Behavioral Simulation**
   - Feed test vector `10101010` into input
   - Watch `disp_data` and `disp_parity` in Wave window
   - Verify values match expectations

4. **Add debug outputs**:
   - Add counters or state indicators to LEDs:
     ```verilog
     assign led[13:8] = state;  // Show FSM state on top 6 LEDs
     ```

**Solution**: Once simulation is correct, bitstream should work. If not, check synthesis warnings.

---

### Problem: 8×8 LED Matrix Not Displaying

**Symptom**: Matrix stays dark or shows random lights (not the parity grid).

**Checklist**:
- [ ] Max7219 module power supply stable (5V or 3.3V)
- [ ] SPI/I2C wiring correct (DIN, CLK, CS pins)
- [ ] `max7219_hvdk.v` pin assignments match FPGA2 constraints
- [ ] Max7219 initialization command sent correctly

**Diagnostic Steps**:

1. **Check Max7219 connections**:
   - VCC → 5V power (or 3.3V)
   - GND → Ground
   - DIN → FPGA2 SPI MOSI (typically PMOD pin)
   - CLK → FPGA2 SPI SCK (typically PMOD pin)
   - CS → FPGA2 SPI CS (typically PMOD pin)

2. **Verify pin assignments in `max7219_hvdk.v`**:
   - Find the pin mapping in the module
   - Cross-reference with `fpga2.xdc` constraints

3. **Check Max7219 initialization**:
   - Module should send initialization commands:
     - Shutdown register OFF
     - Decode mode = No decode
     - Intensity = mid-range
     - Scan limit = 8 digits
   - If initialization fails, matrix will not respond

4. **Test with static pattern**:
   - Hardcode a test pattern instead of HVDK grid:
     ```verilog
     assign matrix_row[7:0] = 8'b10101010;  // Checkerboard
     ```

5. **Measure SPI lines with oscilloscope** (if available):
   - CLK should toggle rapidly during data transfer
   - DIN should have data bits
   - CS should pulse low during transfers

**Solution**: If matrix still dead:
- Verify Max7219 chip with continuity tester
- Try a fresh Max7219 module
- Check SPI timing matches module datasheet (~1-10 MHz)

---

## Timing & Synchronization Issues

### Problem: Delayed or Inconsistent Error Correction

**Symptom**: Sometimes error is corrected immediately, sometimes takes longer.

**Causes**:
1. FSM state transitions not synchronized
2. LFSR seed produces predictable patterns
3. Delay counter overflow

**Fix**:

1. **Check FSM timing**:
   - In `top_fpga2.v`, verify states transition properly:
     ```verilog
     ST_IDLE → ST_CORRUPT → ST_WAIT → ST_CORRECT → ST_SEND → ST_IDLE
     ```

2. **Verify delay counter**:
   ```verilog
   localparam DELAY_2S = 200_000_000;  // 28-bit counter: 0 to 268M
   if (delay_cnt < DELAY_2S - 1) delay_cnt <= delay_cnt + 1;
   ```

3. **Check LFSR randomness**:
   - LFSR should cycle through many values before repeating
   - Current seed: `lfsr <= 8'hAC;`
   - Try different seed: `lfsr <= 8'h73;` or `8'hF5;`

**Solution**: Add debug state outputs to verify FSM progression:
```verilog
assign led[15:13] = state;  // Show current state on LEDs
```

---

### Problem: Data Loss / Missing Bytes

**Symptom**: PuTTY shows some outputs but skips bytes randomly.

**Causes**:
1. UART timing too tight (baud divisor miscalculated)
2. Metastability issues with async inputs
3. Buffer overflow

**Fix**:

1. **Recalculate baud divisor**:
   ```verilog
   BAUD_DIV = CLK_HZ / BAUD_RATE = 100_000_000 / 9600 = 10416 ✓
   ```
   Verify this exact calculation in both `uart_rx2.v` and `uart_tx2.v`.

2. **Add synchronizers for external inputs**:
   - Already done in `top_fpga2.v` for `rst_btn`
   - Check `fpga1_rx` line also has proper CDC (Clock Domain Crossing)

3. **Reduce system clock if necessary**:
   - Try running at 50 MHz instead of 100 MHz (requires XDC change)
   - May help if there are race conditions

**Solution**: Use oscilloscope to verify UART waveform matches expected baud rate timing.

---

## Power & Hardware Issues

### Problem: Board Resets Spontaneously

**Symptom**: FPGA board resets without pressing reset button.

**Causes**:
1. Inadequate power supply (USB current limiting)
2. Brownout detection triggered
3. Overheating

**Fix**:

1. **Use external power supply**:
   - USB may not provide enough current for 2 FPGAs + LED matrix
   - Connect external 5V supply to Basys3 power jack
   - Set jumper **J7 to WALL** position

2. **Check for shorts**:
   - Power down boards
   - Use multimeter to check GND to VCC (should be > 1MΩ resistance)
   - Inspect jumper wires for bent pins or solder bridges

3. **Reduce switching frequency**:
   - If LEDs are toggling very fast, slow down:
     ```verilog
     localparam COUNTER_WIDTH = 20;  // Reduce from 18 for slower toggling
     ```

4. **Improve ventilation**:
   - Ensure board is not in a closed enclosure
   - Check temperature with thermal camera (should be < 60°C)

**Solution**: Most common fix is upgrading to external power supply.

---

### Problem: One Board Won't Program

**Symptom**: Vivado shows "Device not found" or "Programming failed".

**Checklist**:
- [ ] USB cable is firmly connected
- [ ] FPGA board is powered ON (green LED lit)
- [ ] Vivado recognizes the device in Hardware Manager
- [ ] No other instance of Vivado is using the device

**Fix**:

1. **Disconnect and reconnect USB**:
   - Unplug USB
   - Wait 5 seconds
   - Plug back in
   - Watch for Device Manager to detect it

2. **Update FTDI drivers** (for Windows):
   - Download from: https://www.silabs.com/developers/usb-to-uart-bridge-vcp-drivers
   - Or: Search Windows Update for "FTDI" drivers

3. **Kill any zombie Vivado processes**:
   ```bash
   # Linux/macOS:
   pkill -f vivado
   
   # Windows Task Manager: Find and kill javaw.exe or vivado.exe
   ```

4. **Check JTAG cable**:
   - Disconnect JTAG cable from board
   - Re-seat firmly at both ends
   - Try different USB port on laptop

**Solution**: If still stuck, try the **Hardware Server** approach:
- Vivado → Tools → Hardware Manager → Open Hardware Server (automatic)
- May require waiting 30 seconds for server to start

---

## Clock & Synchronization

### Problem: Timing Errors During Implementation

**Symptom**: Vivado reports: "Timing constraints violated" or "Setup time violated".

**Causes**:
1. UART baud rate divisor is too small (clock too fast)
2. Path from FPGA1 RX to processing is critical
3. Max7219 SPI clock too fast

**Fix**:

1. **Add clock period constraint in `.xdc`**:
   ```tcl
   create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]
   ```

2. **Relax timing for UART inputs**:
   ```tcl
   set_false_path -from [get_ports fpga1_rx] -to [all_registers]
   ```

3. **Reduce SPI clock frequency**:
   - In `max7219_hvdk.v`, increase clock divider:
     ```verilog
     localparam SPI_CLK_DIV = 50;  // was 25, now 2× slower
     ```

**Solution**: After fixing, re-run implementation. Check **Vivado → Report → Timing Summary** to verify no violations.

---

## Design & Logic Issues

### Problem: Error Correction Not Working (Always Returns Original)

**Symptom**: Even after injecting bit flip, FPGA2 shows original byte unchanged.

**Likely Cause**: HVDK decoder not calculating syndromes correctly.

**Debug**:

1. **Check HVDK encoder/decoder match**:
   - Ensure both use same parity bit definitions
   - All 6 parity bits (P0-P5) must be calculated identically

2. **Verify syndrome calculation in decoder**:
   ```verilog
   // Should calculate syndromes based on corrupted data
   wire s0 = parity_0_from_received_data;
   wire s1 = parity_1_from_received_data;
   // ...
   // Then use to correct
   ```

3. **Run simulation with known errors**:
   - Inject specific bit flip (e.g., bit 3)
   - Verify syndrome correctly identifies bit 3
   - Watch error correction logic output corrected value

4. **Add test vectors to simulation**:
   - Test all 8 single-bit error positions
   - Verify each is correctly identified and fixed

**Solution**: Most likely the syndrome-to-bit-position mapping is wrong. Review HVDK theory in the code comments.

---

## General Debugging Workflow

When stuck, follow this systematic approach:

1. **Divide and conquer**:
   - Test FPGA1 alone (constant output)
   - Test FPGA2 alone (no FPGA1 input)
   - Test UART loopback on one FPGA

2. **Use simulation early**:
   - Behavioral simulation catches most logic bugs
   - Timing simulation catches clock/synchronization issues
   - Before hardware, verify in sim

3. **Add debug signals**:
   - Output FSM state on LEDs
   - Output counter values on LEDs
   - Use logic analyzer on PMOD pins if available

4. **Test in isolation**:
   - Test UART with constant data
   - Test HVDK with known vectors
   - Test LED display with hardcoded patterns

5. **Incremental complexity**:
   - Start with one byte
   - Then add delay
   - Then add error injection
   - Finally add full pipeline

---

## When All Else Fails

1. **Restart Vivado**: Close and reopen project
2. **Regenerate files**: Delete `.cache/` and `.sim/` directories, resynthesize
3. **Check documentation**: Review Basys3 manual and UART theory
4. **Ask for help**: Open a GitHub issue with:
   - What you're seeing (symptoms)
   - What you've tried
   - Error messages / screenshots
   - Your hardware setup description

---

**Remember**: Most issues are simple (loose wires, wrong COM port, baud rate mismatch). Start with the physical hardware checklist!
