// ============================================================================
// max7219_hvdk.v  -  MAX7219 8x8 LED Matrix, HVDK Animated Controller
//
// SPI protocol (MAX7219 datasheet):
//   - CS low
//   - 16 bits MSB-first; data setup before rising CLK edge
//   - CS high: rising edge latches the word
//   - Min CS-high between words: 50 ns (we give one full half-period)
//
// KEY FIXES vs previous versions:
//   1. No free-running clock divider. spi_clk is 0 whenever CS is high.
//   2. Bit counter is unambiguous: explicit S_CLK_LO / S_CLK_HI phases,
//      shift happens AFTER the rising edge is held, counter decrements then.
//      Bit 15 is presented first; bit 0 is the last rising edge.
//   3. No Verilog tasks, no blocking assignments inside clocked always.
//      cmd_buf is a proper reg array written with <=.
//   4. Init order: DISPTEST OFF first (chip may be stuck in test mode),
//      then decode/intensity/scanlimit, then shutdown->normal, then clear.
//   5. Animation uses PREP/WAIT/TIME sub-states so spi_go is a clean
//      one-cycle pulse and we never re-trigger while SPI is busy.
// ============================================================================
module max7219_hvdk (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data_in,
    input  wire [5:0] parity_in,   // {p5,p4,p3,p2,p1,p0}
    input  wire       update,
    output reg        din,
    output reg        cs_n,
    output reg        spi_clk
);

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
// SPI clock = 100 MHz / (2 * SPI_HALF) = 500 kHz  (MAX7219 max = 10 MHz)
localparam integer SPI_HALF = 100;

// Animation timing at 100 MHz
localparam [27:0] T_DATA = 28'd50_000_000;   // 0.5 s
localparam [27:0] T_HL   = 28'd100_000_000;  // 1.0 s blink phase
localparam [27:0] T_RES  = 28'd30_000_000;   // 0.3 s result hold
localparam [27:0] T_SUM  = 28'd150_000_000;  // 1.5 s summary

// Blink 4 Hz => half-period 12 500 000 clocks
localparam [23:0] BLINK_HALF = 24'd12_500_000;

// HVDK column masks
localparam [7:0] M_P0 = 8'h0F;
localparam [7:0] M_P1 = 8'hF0;
localparam [7:0] M_P2 = 8'h55;
localparam [7:0] M_P3 = 8'hAA;
localparam [7:0] M_P4 = 8'h66;
localparam [7:0] M_P5 = 8'hFF;

// MAX7219 register addresses
localparam [7:0] REG_DECMODE  = 8'h09;
localparam [7:0] REG_INTENSITY= 8'h0A;
localparam [7:0] REG_SCANLIM  = 8'h0B;
localparam [7:0] REG_SHUTDOWN = 8'h0C;
localparam [7:0] REG_DISPTEST = 8'h0F;

// ===========================================================================
// Command buffer (13 slots x 16 bits)
// ===========================================================================
reg [15:0] cmd_buf [0:12];
reg [3:0]  cmd_total;   // number of words to transmit (1..13)

// ===========================================================================
// SPI ENGINE
//
// spi_go   : one-cycle pulse from animation FSM to start transfer
// spi_done : one-cycle pulse from SPI engine when all words transmitted
//
// States:
//   S_IDLE   - wait for spi_go
//   S_CS_LOW - assert CS, load word into shift register
//   S_CLK_LO - CLK=0, DIN=shift[15], count SPI_HALF clocks
//   S_CLK_HI - CLK=1, MAX7219 latches on rising edge, count SPI_HALF clocks
//              at end of phase: shift left, decrement bit_cnt
//              if bit_cnt was 0 (last bit done): go to S_CS_HI
//              else: go back to S_CLK_LO
//   S_CS_HI  - CS=1 (latch word), wait SPI_HALF, then next word or done
// ===========================================================================
reg        spi_go;
reg        spi_done;

localparam [2:0]
    S_IDLE   = 3'd0,
    S_CS_LOW = 3'd1,
    S_CLK_LO = 3'd2,
    S_CLK_HI = 3'd3,
    S_CS_HI  = 3'd4;

reg [2:0]  spi_st;
reg [15:0] spi_shift;
reg [3:0]  spi_bit;    // 15 downto 0
reg [3:0]  spi_idx;    // which cmd_buf word
reg [7:0]  spi_div;    // half-period counter

always @(posedge clk) begin
    if (rst) begin
        spi_st    <= S_IDLE;
        spi_done  <= 1'b0;
        spi_div   <= 8'd0;
        spi_idx   <= 4'd0;
        spi_shift <= 16'd0;
        spi_bit   <= 4'd15;
        din       <= 1'b0;
        cs_n      <= 1'b1;
        spi_clk   <= 1'b0;
    end else begin
        spi_done <= 1'b0;

        case (spi_st)

            S_IDLE: begin
                cs_n    <= 1'b1;
                spi_clk <= 1'b0;
                din     <= 1'b0;
                if (spi_go) begin
                    spi_idx <= 4'd0;
                    spi_st  <= S_CS_LOW;
                end
            end

            // Assert CS, load current word, reset bit counter and divider
            S_CS_LOW: begin
                cs_n      <= 1'b0;
                spi_clk   <= 1'b0;
                spi_shift <= cmd_buf[spi_idx];
                spi_bit   <= 4'd15;
                spi_div   <= 8'd0;
                din       <= cmd_buf[spi_idx][15];  // pre-load MSB
                spi_st    <= S_CLK_LO;
            end

            // CLK low half-period: DIN is already valid (set at end of CLK_HI
            // or at CS_LOW). Just count, then raise CLK.
            S_CLK_LO: begin
                spi_clk <= 1'b0;
                if (spi_div == SPI_HALF - 1) begin
                    spi_div <= 8'd0;
                    spi_st  <= S_CLK_HI;
                end else begin
                    spi_div <= spi_div + 8'd1;
                end
            end

            // CLK high half-period: MAX7219 latches DIN on the rising edge
            // (which happened at the S_CLK_LO->S_CLK_HI transition).
            // At the end of this phase: shift left, present next bit on DIN,
            // decrement counter, decide next state.
            S_CLK_HI: begin
                spi_clk <= 1'b1;
                if (spi_div == SPI_HALF - 1) begin
                    spi_div   <= 8'd0;
                    spi_clk   <= 1'b0;                           // CLK back low
                    spi_shift <= {spi_shift[14:0], 1'b0};        // shift
                    din       <= spi_shift[14];                   // next bit
                    if (spi_bit == 4'd0) begin
                        // Last bit just latched — deassert CS
                        spi_st <= S_CS_HI;
                    end else begin
                        spi_bit <= spi_bit - 4'd1;
                        spi_st  <= S_CLK_LO;
                    end
                end else begin
                    spi_div <= spi_div + 8'd1;
                end
            end

            // CS high — word latched into MAX7219.
            // Hold for one half-period, then next word or finish.
            S_CS_HI: begin
                cs_n    <= 1'b1;
                spi_clk <= 1'b0;
                din     <= 1'b0;
                if (spi_div == SPI_HALF - 1) begin
                    spi_div <= 8'd0;
                    if (spi_idx == cmd_total - 1) begin
                        spi_done <= 1'b1;
                        spi_st   <= S_IDLE;
                    end else begin
                        spi_idx  <= spi_idx + 4'd1;
                        spi_st   <= S_CS_LOW;
                    end
                end else begin
                    spi_div <= spi_div + 8'd1;
                end
            end

            default: spi_st <= S_IDLE;
        endcase
    end
end

// ===========================================================================
// BLINK GENERATOR  4 Hz
// ===========================================================================
reg [23:0] blink_cnt;
reg        blink;
reg        blink_prev;
reg        blink_tog;   // one-cycle pulse on each blink edge

always @(posedge clk) begin
    if (rst) begin
        blink_cnt  <= 24'd0;
        blink      <= 1'b0;
        blink_prev <= 1'b0;
        blink_tog  <= 1'b0;
    end else begin
        blink_tog  <= 1'b0;
        blink_prev <= blink;
        if (blink != blink_prev) blink_tog <= 1'b1;
        if (blink_cnt == BLINK_HALF - 1) begin
            blink_cnt <= 24'd0;
            blink     <= ~blink;
        end else begin
            blink_cnt <= blink_cnt + 24'd1;
        end
    end
end

// ===========================================================================
// ANIMATION FSM
// ===========================================================================
localparam [4:0]
    A_POWERUP = 5'd0,
    A_IDLE    = 5'd1,
    A_DATA    = 5'd2,
    A_P0_HL   = 5'd3,  A_P0_RES  = 5'd4,
    A_P1_HL   = 5'd5,  A_P1_RES  = 5'd6,
    A_P2_HL   = 5'd7,  A_P2_RES  = 5'd8,
    A_P3_HL   = 5'd9,  A_P3_RES  = 5'd10,
    A_P4_HL   = 5'd11, A_P4_RES  = 5'd12,
    A_P5_HL   = 5'd13, A_P5_RES  = 5'd14,
    A_SUMMARY = 5'd15;

// Sub-states for each animation step
localparam [1:0]
    AS_PREP = 2'd0,   // load cmd_buf and fire spi_go
    AS_WAIT = 2'd1,   // wait for spi_done
    AS_TIME = 2'd2;   // count animation timer (re-send on blink_tog for HL)

reg [4:0]  anim;
reg [1:0]  asub;
reg [27:0] atimer;
reg [7:0]  ld;
reg [5:0]  lp;

wire [7:0] rp0 = lp[0] ? 8'hFF : 8'h00;
wire [7:0] rp1 = lp[1] ? 8'hFF : 8'h00;
wire [7:0] rp2 = lp[2] ? 8'hFF : 8'h00;
wire [7:0] rp3 = lp[3] ? 8'hFF : 8'h00;
wire [7:0] rp4 = lp[4] ? 8'hFF : 8'h00;
wire [7:0] rp5 = lp[5] ? 8'hFF : 8'h00;

// Convenience: load 8-row display (rows 1-8) into cmd_buf[0..7]
// Written inline in each state below (no tasks).

// Powerup sub-step counter (we need two SPI bursts: init13 then row8 clear)
reg pu_step;

always @(posedge clk) begin
    if (rst) begin
        anim       <= A_POWERUP;
        asub       <= AS_PREP;
        atimer     <= 28'd0;
        spi_go     <= 1'b0;
        ld         <= 8'h00;
        lp         <= 6'h00;
        pu_step    <= 1'b0;
        cmd_total  <= 4'd0;
        begin : init_buf
            integer i;
            for (i = 0; i < 13; i = i + 1) cmd_buf[i] <= 16'd0;
        end
    end else begin
        spi_go <= 1'b0;   // default: no trigger

        // Capture new data and restart animation (except during power-up)
        if (update && (anim != A_POWERUP)) begin
            ld     <= data_in;
            lp     <= parity_in;
            anim   <= A_DATA;
            asub   <= AS_PREP;
            atimer <= 28'd0;
        end

        case (anim)

            // ================================================================
            // POWER-UP INIT
            // Step 0: send 13 words (test-off, config, shutdown seq, clear r1-7)
            // Step 1: send 1 word  (clear row 8)
            // ================================================================
            A_POWERUP: begin
                case (asub)
                    AS_PREP: begin
                        if (pu_step == 1'b0) begin
                            // --- 13-word init burst ---
                            cmd_buf[0]  <= {REG_DISPTEST,  8'h00};  // test OFF (critical: do first)
                            cmd_buf[1]  <= {REG_DECMODE,   8'h00};  // no BCD decode
                            cmd_buf[2]  <= {REG_INTENSITY, 8'h08};  // 50% brightness
                            cmd_buf[3]  <= {REG_SCANLIM,   8'h07};  // scan all 8 rows
                            cmd_buf[4]  <= {REG_SHUTDOWN,  8'h00};  // enter shutdown
                            cmd_buf[5]  <= {REG_SHUTDOWN,  8'h01};  // exit shutdown (normal op)
                            cmd_buf[6]  <= {8'h01, 8'h00};          // clear row 1
                            cmd_buf[7]  <= {8'h02, 8'h00};
                            cmd_buf[8]  <= {8'h03, 8'h00};
                            cmd_buf[9]  <= {8'h04, 8'h00};
                            cmd_buf[10] <= {8'h05, 8'h00};
                            cmd_buf[11] <= {8'h06, 8'h00};
                            cmd_buf[12] <= {8'h07, 8'h00};
                            cmd_total   <= 4'd13;
                        end else begin
                            // --- clear row 8 ---
                            cmd_buf[0] <= {8'h08, 8'h00};
                            cmd_total  <= 4'd1;
                        end
                        spi_go <= 1'b1;
                        asub   <= AS_WAIT;
                    end
                    AS_WAIT: begin
                        if (spi_done) begin
                            if (pu_step == 1'b0) begin
                                pu_step <= 1'b1;
                                asub    <= AS_PREP;   // send row-8 clear
                            end else begin
                                anim  <= A_IDLE;
                                asub  <= AS_PREP;
                            end
                        end
                    end
                    default: asub <= AS_PREP;
                endcase
            end

            // ================================================================
            A_IDLE: begin
                asub <= AS_PREP;
                // wait for update (captured at top of always block)
            end

            // ================================================================
            // DATA: row1=data byte, rows2-8=blank
            // ================================================================
            A_DATA: begin
                case (asub)
                    AS_PREP: begin
                        cmd_buf[0] <= {8'h01, ld};
                        cmd_buf[1] <= {8'h02, 8'h00};
                        cmd_buf[2] <= {8'h03, 8'h00};
                        cmd_buf[3] <= {8'h04, 8'h00};
                        cmd_buf[4] <= {8'h05, 8'h00};
                        cmd_buf[5] <= {8'h06, 8'h00};
                        cmd_buf[6] <= {8'h07, 8'h00};
                        cmd_buf[7] <= {8'h08, 8'h00};
                        cmd_total  <= 4'd8;
                        spi_go     <= 1'b1;
                        asub       <= AS_WAIT;
                    end
                    AS_WAIT: if (spi_done) begin atimer <= 28'd0; asub <= AS_TIME; end
                    AS_TIME: begin
                        atimer <= atimer + 28'd1;
                        if (atimer >= T_DATA) begin
                            anim <= A_P0_HL; asub <= AS_PREP; atimer <= 28'd0;
                        end
                    end
                    default: asub <= AS_PREP;
                endcase
            end

            // ================================================================
            // P0 HL: row1=data, row2=blink M_P0, rows3-8=blank
            // ================================================================
            A_P0_HL: begin
                case (asub)
                    AS_PREP: begin
                        cmd_buf[0] <= {8'h01, ld};
                        cmd_buf[1] <= {8'h02, blink ? M_P0 : 8'h00};
                        cmd_buf[2] <= {8'h03, 8'h00};
                        cmd_buf[3] <= {8'h04, 8'h00};
                        cmd_buf[4] <= {8'h05, 8'h00};
                        cmd_buf[5] <= {8'h06, 8'h00};
                        cmd_buf[6] <= {8'h07, 8'h00};
                        cmd_buf[7] <= {8'h08, 8'h00};
                        cmd_total  <= 4'd8;
                        spi_go     <= 1'b1;
                        asub       <= AS_WAIT;
                    end
                    AS_WAIT: if (spi_done) begin asub <= AS_TIME; end
                    AS_TIME: begin
                        atimer <= atimer + 28'd1;
                        if      (atimer >= T_HL)  begin anim <= A_P0_RES; asub <= AS_PREP; atimer <= 28'd0; end
                        else if (blink_tog)        begin asub <= AS_PREP; end
                    end
                    default: asub <= AS_PREP;
                endcase
            end

            // P0 RES: row2=rp0 steady
            A_P0_RES: begin
                case (asub)
                    AS_PREP: begin
                        cmd_buf[0] <= {8'h01, ld};
                        cmd_buf[1] <= {8'h02, rp0};
                        cmd_buf[2] <= {8'h03, 8'h00};
                        cmd_buf[3] <= {8'h04, 8'h00};
                        cmd_buf[4] <= {8'h05, 8'h00};
                        cmd_buf[5] <= {8'h06, 8'h00};
                        cmd_buf[6] <= {8'h07, 8'h00};
                        cmd_buf[7] <= {8'h08, 8'h00};
                        cmd_total  <= 4'd8;
                        spi_go     <= 1'b1;
                        asub       <= AS_WAIT;
                    end
                    AS_WAIT: if (spi_done) begin atimer <= 28'd0; asub <= AS_TIME; end
                    AS_TIME: begin
                        atimer <= atimer + 28'd1;
                        if (atimer >= T_RES) begin anim <= A_P1_HL; asub <= AS_PREP; atimer <= 28'd0; end
                    end
                    default: asub <= AS_PREP;
                endcase
            end

            // ================================================================
            // P1 HL: row3=blink M_P1
            // ================================================================
            A_P1_HL: begin
                case (asub)
                    AS_PREP: begin
                        cmd_buf[0] <= {8'h01, ld};
                        cmd_buf[1] <= {8'h02, rp0};
                        cmd_buf[2] <= {8'h03, blink ? M_P1 : 8'h00};
                        cmd_buf[3] <= {8'h04, 8'h00};
                        cmd_buf[4] <= {8'h05, 8'h00};
                        cmd_buf[5] <= {8'h06, 8'h00};
                        cmd_buf[6] <= {8'h07, 8'h00};
                        cmd_buf[7] <= {8'h08, 8'h00};
                        cmd_total  <= 4'd8;
                        spi_go     <= 1'b1;
                        asub       <= AS_WAIT;
                    end
                    AS_WAIT: if (spi_done) begin asub <= AS_TIME; end
                    AS_TIME: begin
                        atimer <= atimer + 28'd1;
                        if      (atimer >= T_HL) begin anim <= A_P1_RES; asub <= AS_PREP; atimer <= 28'd0; end
                        else if (blink_tog)       begin asub <= AS_PREP; end
                    end
                    default: asub <= AS_PREP;
                endcase
            end

            A_P1_RES: begin
                case (asub)
                    AS_PREP: begin
                        cmd_buf[0] <= {8'h01, ld};
                        cmd_buf[1] <= {8'h02, rp0};
                        cmd_buf[2] <= {8'h03, rp1};
                        cmd_buf[3] <= {8'h04, 8'h00};
                        cmd_buf[4] <= {8'h05, 8'h00};
                        cmd_buf[5] <= {8'h06, 8'h00};
                        cmd_buf[6] <= {8'h07, 8'h00};
                        cmd_buf[7] <= {8'h08, 8'h00};
                        cmd_total  <= 4'd8;
                        spi_go     <= 1'b1;
                        asub       <= AS_WAIT;
                    end
                    AS_WAIT: if (spi_done) begin atimer <= 28'd0; asub <= AS_TIME; end
                    AS_TIME: begin
                        atimer <= atimer + 28'd1;
                        if (atimer >= T_RES) begin anim <= A_P2_HL; asub <= AS_PREP; atimer <= 28'd0; end
                    end
                    default: asub <= AS_PREP;
                endcase
            end

            // ================================================================
            // P2 HL: row4=blink M_P2
            // ================================================================
            A_P2_HL: begin
                case (asub)
                    AS_PREP: begin
                        cmd_buf[0] <= {8'h01, ld};
                        cmd_buf[1] <= {8'h02, rp0};
                        cmd_buf[2] <= {8'h03, rp1};
                        cmd_buf[3] <= {8'h04, blink ? M_P2 : 8'h00};
                        cmd_buf[4] <= {8'h05, 8'h00};
                        cmd_buf[5] <= {8'h06, 8'h00};
                        cmd_buf[6] <= {8'h07, 8'h00};
                        cmd_buf[7] <= {8'h08, 8'h00};
                        cmd_total  <= 4'd8;
                        spi_go     <= 1'b1;
                        asub       <= AS_WAIT;
                    end
                    AS_WAIT: if (spi_done) begin asub <= AS_TIME; end
                    AS_TIME: begin
                        atimer <= atimer + 28'd1;
                        if      (atimer >= T_HL) begin anim <= A_P2_RES; asub <= AS_PREP; atimer <= 28'd0; end
                        else if (blink_tog)       begin asub <= AS_PREP; end
                    end
                    default: asub <= AS_PREP;
                endcase
            end

            A_P2_RES: begin
                case (asub)
                    AS_PREP: begin
                        cmd_buf[0] <= {8'h01, ld};
                        cmd_buf[1] <= {8'h02, rp0};
                        cmd_buf[2] <= {8'h03, rp1};
                        cmd_buf[3] <= {8'h04, rp2};
                        cmd_buf[4] <= {8'h05, 8'h00};
                        cmd_buf[5] <= {8'h06, 8'h00};
                        cmd_buf[6] <= {8'h07, 8'h00};
                        cmd_buf[7] <= {8'h08, 8'h00};
                        cmd_total  <= 4'd8;
                        spi_go     <= 1'b1;
                        asub       <= AS_WAIT;
                    end
                    AS_WAIT: if (spi_done) begin atimer <= 28'd0; asub <= AS_TIME; end
                    AS_TIME: begin
                        atimer <= atimer + 28'd1;
                        if (atimer >= T_RES) begin anim <= A_P3_HL; asub <= AS_PREP; atimer <= 28'd0; end
                    end
                    default: asub <= AS_PREP;
                endcase
            end

            // ================================================================
            // P3 HL: row5=blink M_P3
            // ================================================================
            A_P3_HL: begin
                case (asub)
                    AS_PREP: begin
                        cmd_buf[0] <= {8'h01, ld};
                        cmd_buf[1] <= {8'h02, rp0};
                        cmd_buf[2] <= {8'h03, rp1};
                        cmd_buf[3] <= {8'h04, rp2};
                        cmd_buf[4] <= {8'h05, blink ? M_P3 : 8'h00};
                        cmd_buf[5] <= {8'h06, 8'h00};
                        cmd_buf[6] <= {8'h07, 8'h00};
                        cmd_buf[7] <= {8'h08, 8'h00};
                        cmd_total  <= 4'd8;
                        spi_go     <= 1'b1;
                        asub       <= AS_WAIT;
                    end
                    AS_WAIT: if (spi_done) begin asub <= AS_TIME; end
                    AS_TIME: begin
                        atimer <= atimer + 28'd1;
                        if      (atimer >= T_HL) begin anim <= A_P3_RES; asub <= AS_PREP; atimer <= 28'd0; end
                        else if (blink_tog)       begin asub <= AS_PREP; end
                    end
                    default: asub <= AS_PREP;
                endcase
            end

            A_P3_RES: begin
                case (asub)
                    AS_PREP: begin
                        cmd_buf[0] <= {8'h01, ld};
                        cmd_buf[1] <= {8'h02, rp0};
                        cmd_buf[2] <= {8'h03, rp1};
                        cmd_buf[3] <= {8'h04, rp2};
                        cmd_buf[4] <= {8'h05, rp3};
                        cmd_buf[5] <= {8'h06, 8'h00};
                        cmd_buf[6] <= {8'h07, 8'h00};
                        cmd_buf[7] <= {8'h08, 8'h00};
                        cmd_total  <= 4'd8;
                        spi_go     <= 1'b1;
                        asub       <= AS_WAIT;
                    end
                    AS_WAIT: if (spi_done) begin atimer <= 28'd0; asub <= AS_TIME; end
                    AS_TIME: begin
                        atimer <= atimer + 28'd1;
                        if (atimer >= T_RES) begin anim <= A_P4_HL; asub <= AS_PREP; atimer <= 28'd0; end
                    end
                    default: asub <= AS_PREP;
                endcase
            end

            // ================================================================
            // P4 HL: row6=blink M_P4
            // ================================================================
            A_P4_HL: begin
                case (asub)
                    AS_PREP: begin
                        cmd_buf[0] <= {8'h01, ld};
                        cmd_buf[1] <= {8'h02, rp0};
                        cmd_buf[2] <= {8'h03, rp1};
                        cmd_buf[3] <= {8'h04, rp2};
                        cmd_buf[4] <= {8'h05, rp3};
                        cmd_buf[5] <= {8'h06, blink ? M_P4 : 8'h00};
                        cmd_buf[6] <= {8'h07, 8'h00};
                        cmd_buf[7] <= {8'h08, 8'h00};
                        cmd_total  <= 4'd8;
                        spi_go     <= 1'b1;
                        asub       <= AS_WAIT;
                    end
                    AS_WAIT: if (spi_done) begin asub <= AS_TIME; end
                    AS_TIME: begin
                        atimer <= atimer + 28'd1;
                        if      (atimer >= T_HL) begin anim <= A_P4_RES; asub <= AS_PREP; atimer <= 28'd0; end
                        else if (blink_tog)       begin asub <= AS_PREP; end
                    end
                    default: asub <= AS_PREP;
                endcase
            end

            A_P4_RES: begin
                case (asub)
                    AS_PREP: begin
                        cmd_buf[0] <= {8'h01, ld};
                        cmd_buf[1] <= {8'h02, rp0};
                        cmd_buf[2] <= {8'h03, rp1};
                        cmd_buf[3] <= {8'h04, rp2};
                        cmd_buf[4] <= {8'h05, rp3};
                        cmd_buf[5] <= {8'h06, rp4};
                        cmd_buf[6] <= {8'h07, 8'h00};
                        cmd_buf[7] <= {8'h08, 8'h00};
                        cmd_total  <= 4'd8;
                        spi_go     <= 1'b1;
                        asub       <= AS_WAIT;
                    end
                    AS_WAIT: if (spi_done) begin atimer <= 28'd0; asub <= AS_TIME; end
                    AS_TIME: begin
                        atimer <= atimer + 28'd1;
                        if (atimer >= T_RES) begin anim <= A_P5_HL; asub <= AS_PREP; atimer <= 28'd0; end
                    end
                    default: asub <= AS_PREP;
                endcase
            end

            // ================================================================
            // P5 HL: row7=blink M_P5 (global XOR — all cols)
            // ================================================================
            A_P5_HL: begin
                case (asub)
                    AS_PREP: begin
                        cmd_buf[0] <= {8'h01, ld};
                        cmd_buf[1] <= {8'h02, rp0};
                        cmd_buf[2] <= {8'h03, rp1};
                        cmd_buf[3] <= {8'h04, rp2};
                        cmd_buf[4] <= {8'h05, rp3};
                        cmd_buf[5] <= {8'h06, rp4};
                        cmd_buf[6] <= {8'h07, blink ? M_P5 : 8'h00};
                        cmd_buf[7] <= {8'h08, 8'h00};
                        cmd_total  <= 4'd8;
                        spi_go     <= 1'b1;
                        asub       <= AS_WAIT;
                    end
                    AS_WAIT: if (spi_done) begin asub <= AS_TIME; end
                    AS_TIME: begin
                        atimer <= atimer + 28'd1;
                        if      (atimer >= T_HL) begin anim <= A_P5_RES; asub <= AS_PREP; atimer <= 28'd0; end
                        else if (blink_tog)       begin asub <= AS_PREP; end
                    end
                    default: asub <= AS_PREP;
                endcase
            end

            A_P5_RES: begin
                case (asub)
                    AS_PREP: begin
                        cmd_buf[0] <= {8'h01, ld};
                        cmd_buf[1] <= {8'h02, rp0};
                        cmd_buf[2] <= {8'h03, rp1};
                        cmd_buf[3] <= {8'h04, rp2};
                        cmd_buf[4] <= {8'h05, rp3};
                        cmd_buf[5] <= {8'h06, rp4};
                        cmd_buf[6] <= {8'h07, rp5};
                        cmd_buf[7] <= {8'h08, 8'h00};
                        cmd_total  <= 4'd8;
                        spi_go     <= 1'b1;
                        asub       <= AS_WAIT;
                    end
                    AS_WAIT: if (spi_done) begin atimer <= 28'd0; asub <= AS_TIME; end
                    AS_TIME: begin
                        atimer <= atimer + 28'd1;
                        if (atimer >= T_RES) begin anim <= A_SUMMARY; asub <= AS_PREP; atimer <= 28'd0; end
                    end
                    default: asub <= AS_PREP;
                endcase
            end

            // ================================================================
            // SUMMARY: hold full display for T_SUM, then idle
            // ================================================================
            A_SUMMARY: begin
                atimer <= atimer + 28'd1;
                if (atimer >= T_SUM) begin
                    atimer <= 28'd0;
                    anim   <= A_IDLE;
                    asub   <= AS_PREP;
                end
            end

            default: begin anim <= A_IDLE; asub <= AS_PREP; end
        endcase
    end
end

endmodule
