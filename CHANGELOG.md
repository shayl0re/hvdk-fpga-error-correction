# Changelog

All notable changes to the HVDK Error Correction project will be documented in this file.

---

## [1.0.0] - 2026-05-23

### Initial Release

**Features**:
- ✅ Dual Basys3 FPGA system for HVDK-based error correction
- ✅ UART communication between FPGAs at 9600 baud (8N1)
- ✅ Real-time single-bit error injection on FPGA2
- ✅ HVDK parity encoding (64-bit → 96-bit frame with 6 parity bits)
- ✅ Syndrome-based single-bit error correction
- ✅ 8×8 LED matrix visualization (Max7219 driver)
- ✅ Real-time LED display of corrupted & corrected bytes
- ✅ PuTTY terminal output of corrected 8-bit binary strings
- ✅ Configurable error injection delay (default: 2 seconds)
- ✅ Free-running LFSR for pseudo-random bit selection

**Hardware**:
- Two Basys3 FPGA boards (xc7a35tcpg236-1)
- Max7219-based 8×8 LED matrix module
- Jumper wire UART connections (PMOD JA)

**Software**:
- Vivado synthesis & implementation ready
- PuTTY terminal configuration guide
- Complete pin constraint files (.xdc)
- Comprehensive setup and troubleshooting documentation

**Documentation**:
- README.md with system overview
- SETUP_GUIDE.md for hardware assembly and Vivado configuration
- TROUBLESHOOTING.md for common issues
- Block diagram showing data flow
- Bill of Materials

### File Structure

```
hvdk-fpga-error-correction/
├── fpga1/
│   ├── verilog/
│   │   ├── top_fpga1.v
│   │   ├── uart_rx.v
│   │   ├── uart_tx.v
│   │   └── max7219_hvdk.v
│   └── constraints/
│       └── fpga1.xdc
├── fpga2/
│   ├── verilog/
│   │   ├── top_fpga2.v
│   │   ├── uart_rx2.v
│   │   ├── uart_tx2.v
│   │   └── hvdk_decoder.v (if included)
│   └── constraints/
│       └── fpga2.xdc
├── docs/
│   ├── SETUP_GUIDE.md
│   ├── TROUBLESHOOTING.md
│   └── HVDK_THEORY.md (future)
├── images/
│   ├── block_diagram.svg
│   ├── (hardware photos - optional)
│   └── (LED matrix examples - optional)
├── README.md
├── CHANGELOG.md (this file)
├── .gitignore
└── LICENSE (future)
```

### Known Limitations

- Single-bit error correction only (multi-bit errors will be detected but not corrected)
- UART baud rate fixed at 9600 (adjustable via code)
- 8×8 LED matrix controlled via SPI/I2C (pin configuration in max7219_hvdk.v)
- Error injection delay fixed at 2 seconds (adjustable via code)
- No persistent storage or logging (real-time display only)

### Future Enhancements

- [ ] Multi-bit error detection (extended Hamming codes)
- [ ] Logging to SD card or external memory
- [ ] Real-time error statistics display
- [ ] Higher baud rate support (115200+)
- [ ] Graphical interface on PC (Qt/Python)
- [ ] Simulation testbenches for behavioral verification
- [ ] Support for larger data frames (>8 bits)
- [ ] Temperature/performance monitoring
- [ ] Web dashboard for remote monitoring

---

## Development Notes

### HVDK Parity Scheme

The HVDK method encodes 64 data bits arranged as an 8×8 grid:

```
Grid positions (row, col):
(0,0) (0,1) (0,2) (0,3) (0,4) (0,5) (0,6) (0,7)
(1,0) (1,1) (1,2) (1,3) (1,4) (1,5) (1,6) (1,7)
...
(7,0) (7,1) (7,2) (7,3) (7,4) (7,5) (7,6) (7,7)
```

**Parity bits** (P0-P5):
- **P0**: XOR of all even rows (0, 2, 4, 6)
- **P1**: XOR of all even columns (0, 2, 4, 6)
- **P2**: XOR of main diagonal + wrapping diagonals
- **P3**: XOR of anti-diagonal + wrapping anti-diagonals
- **P4**: XOR of all cells reachable by knight's move from (0,0)
- **P5**: Overall parity (XOR of all data bits)

**Error correction**:
1. Calculate syndromes (S0-S5) from received data
2. Syndrome value encodes the error position
3. XOR that position with received bit to correct

### Testing

For development and debugging:
1. **Behavioral simulation** in Vivado — verify HVDK logic on test vectors
2. **Timing simulation** — check UART timing at 9600 baud
3. **Hardware testing** — manual verification with PuTTY
4. **Edge cases** — all-zeros, all-ones, single-bit variations

### References

- HVDK parity scheme: Classical error-correcting code, extension of Hamming codes
- Basys3 reference: https://digilent.com/reference/programmable-logic/basys-3/start
- Max7219 datasheet: https://datasheets.maximintegrated.com/en/ds/MAX7219.pdf
- Vivado documentation: https://docs.xilinx.com/

---

## How to Contribute

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Commit changes (`git commit -am 'Add your feature'`)
4. Push to branch (`git push origin feature/your-feature`)
5. Open a pull request

**Guidelines**:
- Test changes in Vivado simulation before hardware
- Update documentation if changing pin assignments or baud rates
- Add comments for non-obvious Verilog logic
- Include test cases for new modules

---

## License

This project is released under the MIT License. See LICENSE file for details.

---

## Contact & Support

For questions, issues, or improvements:
- Open a GitHub issue with detailed description
- Include hardware setup, software versions, and error messages
- Provide minimal reproducible example if possible

---

**Last updated**: May 23, 2026
**Maintainer**: Shivani
