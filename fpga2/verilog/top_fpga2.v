// ============================================================================
// top_fpga2.v  -  Basys3 FPGA2
//
// * Receives raw 8-bit byte from FPGA1 via PMOD JA pin1
// * Calculates HVDK parity (P0-P5)
// * Randomly flips ONE bit in the received byte
// * Displays the CORRUPTED byte on LD0-LD7 and its (wrong) parity on LD8-LD13
// * After 2-second delay, CORRECTS the data back to original
// * Displays the CORRECT byte+parity on LEDs
// * Sends correct binary string "XXXXXXXX\r\n" to PC2 via USB-UART
//
// Random bit selection uses a free-running 3-bit LFSR seeded from timing,
// giving a pseudo-random bit index 0-7 each time.
//
// PORTS (match fpga2.xdc exactly):
//   clk, rst_btn, fpga1_rx, pc_tx, led[13:0]
// ============================================================================
module top_fpga2 (
    input  wire        clk,
    input  wire        rst_btn,
    input  wire        fpga1_rx,
    output wire        pc_tx,
    output wire [13:0] led
);

localparam CLK_HZ    = 100_000_000;
localparam BAUD_RATE = 9600;
localparam BAUD_DIV  = CLK_HZ / BAUD_RATE; // 10416

// 2 seconds at 100 MHz
localparam DELAY_2S  = 200_000_000;

// --------------------------------------------------------------------------
// Reset synchroniser
// --------------------------------------------------------------------------
reg rst_s1, rst_s2;
always @(posedge clk) begin rst_s1<=rst_btn; rst_s2<=rst_s1; end
wire rst = rst_s2;

// --------------------------------------------------------------------------
// Free-running 8-bit LFSR for pseudo-random bit selection
// Polynomial x^8 + x^6 + x^5 + x^4 + 1  (taps: bits 7,5,4,3)
// Runs continuously so the tap point at rx time is unpredictable
// --------------------------------------------------------------------------
reg [7:0] lfsr;
always @(posedge clk) begin
    if (rst)
        lfsr <= 8'hAC; // non-zero seed
    else
        lfsr <= {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
end

// Map 8-bit LFSR output to a 3-bit flip position (0-7)
// Just use lower 3 bits - LFSR distribution is good enough
wire [2:0] flip_pos = lfsr[2:0];

// --------------------------------------------------------------------------
// UART RX - receives raw byte from FPGA1
// --------------------------------------------------------------------------
wire [7:0] rx_byte;
wire       rx_done;

uart_rx2 #(.BAUD_DIV(BAUD_DIV)) u_rx (
    .clk      (clk),
    .rst      (rst),
    .rx       (fpga1_rx),
    .data_out (rx_byte),
    .data_rdy (rx_done)
);

// --------------------------------------------------------------------------
// Data registers
// --------------------------------------------------------------------------
reg [7:0] orig_data;       // original received byte
reg [7:0] flip_mask;       // one-hot mask for the flipped bit
reg [7:0] corrupt_data;    // byte with one bit flipped
reg [7:0] disp_data;       // currently displayed byte
reg [5:0] disp_parity;     // parity of currently displayed byte

// --------------------------------------------------------------------------
// Parity calculation (combinational) for currently displayed data
// --------------------------------------------------------------------------
wire dp0 = disp_data[0]^disp_data[1]^disp_data[2]^disp_data[3];
wire dp1 = disp_data[4]^disp_data[5]^disp_data[6]^disp_data[7];
wire dp2 = disp_data[0]^disp_data[2]^disp_data[4]^disp_data[6];
wire dp3 = disp_data[1]^disp_data[3]^disp_data[5]^disp_data[7];
wire dp4 = disp_data[1]^disp_data[2]^disp_data[5]^disp_data[6];
wire dp5 = ^disp_data;

// --------------------------------------------------------------------------
// Main FSM
// States:
//   IDLE         - waiting for new byte
//   CORRUPT      - flip a bit, display corrupt, start 2s timer
//   WAIT         - hold corrupt display for 2s
//   CORRECT      - restore original, update LEDs, send to PC2
//   SEND         - send binary string via UART
// --------------------------------------------------------------------------
localparam ST_IDLE    = 3'd0;
localparam ST_CORRUPT = 3'd1;
localparam ST_WAIT    = 3'd2;
localparam ST_CORRECT = 3'd3;
localparam ST_SEND    = 3'd4;

reg [2:0]  state;
reg [27:0] delay_cnt;   // 28 bits: can count to 268M > 200M
reg        send_trig;   // pulse to start UART send SM

always @(posedge clk) begin
    if (rst) begin
        state        <= ST_IDLE;
        orig_data    <= 8'h00;
        flip_mask    <= 8'h01;
        corrupt_data <= 8'h00;
        disp_data    <= 8'h00;
        disp_parity  <= 6'h00;
        delay_cnt    <= 0;
        send_trig    <= 1'b0;
    end else begin
        send_trig <= 1'b0;

        // Update parity continuously from disp_data
        disp_parity <= {dp5,dp4,dp3,dp2,dp1,dp0};

        case (state)
            // ---- Wait for FPGA1 byte ----
            ST_IDLE: begin
                if (rx_done) begin
                    orig_data <= rx_byte;
                    state     <= ST_CORRUPT;
                end
            end

            // ---- Apply random bit flip ----
            ST_CORRUPT: begin
                // Sample LFSR now for flip position
                case (flip_pos)
                    3'd0: flip_mask <= 8'b00000001;
                    3'd1: flip_mask <= 8'b00000010;
                    3'd2: flip_mask <= 8'b00000100;
                    3'd3: flip_mask <= 8'b00001000;
                    3'd4: flip_mask <= 8'b00010000;
                    3'd5: flip_mask <= 8'b00100000;
                    3'd6: flip_mask <= 8'b01000000;
                    3'd7: flip_mask <= 8'b10000000;
                endcase
                corrupt_data <= orig_data ^ (8'd1 << flip_pos);
                disp_data    <= orig_data ^ (8'd1 << flip_pos);
                delay_cnt    <= 0;
                state        <= ST_WAIT;
            end

            // ---- Hold corrupt display for 2 seconds ----
            ST_WAIT: begin
                // disp_data = corrupt_data (already set)
                if (delay_cnt < DELAY_2S - 1)
                    delay_cnt <= delay_cnt + 1;
                else begin
                    delay_cnt <= 0;
                    state     <= ST_CORRECT;
                end
            end

            // ---- Correct: restore original byte ----
            ST_CORRECT: begin
                disp_data <= orig_data;
                send_trig <= 1'b1;   // trigger UART send
                state     <= ST_SEND;
            end

            // ---- Wait for UART send to finish, then go idle ----
            ST_SEND: begin
                // send FSM handles transmission; we just wait one cycle
                // The send SM signals done via its own state; we go IDLE
                // once it's back to state 0.
                if (send_idle)
                    state <= ST_IDLE;
            end

            default: state <= ST_IDLE;
        endcase
    end
end

// --------------------------------------------------------------------------
// LED outputs  - show disp_data (corrupted or corrected)
// --------------------------------------------------------------------------
assign led[7:0]  = disp_data;
assign led[13:8] = disp_parity;

// --------------------------------------------------------------------------
// UART TX to PC2 - sends correct binary string "XXXXXXXX\r\n"
// Triggered by send_trig pulse; sends orig_data (not corrupt)
// --------------------------------------------------------------------------
wire tx_busy;
reg  tx_start;
reg  [7:0] tx_byte_r;

uart_tx2 #(.BAUD_DIV(BAUD_DIV)) u_tx (
    .clk      (clk),
    .rst      (rst),
    .tx_start (tx_start),
    .tx_byte  (tx_byte_r),
    .tx       (pc_tx),
    .tx_busy  (tx_busy)
);

// Send state machine: 8 bits + CR + LF = 10 chars
reg [3:0] snd_state;
reg [3:0] snd_bit;
reg [7:0] snd_data;
wire      send_idle = (snd_state == 4'd0);

always @(posedge clk) begin
    if (rst) begin
        snd_state <= 4'd0;
        tx_start  <= 1'b0;
        tx_byte_r <= 8'h00;
        snd_bit   <= 4'd7;
        snd_data  <= 8'h00;
    end else begin
        tx_start <= 1'b0;
        case (snd_state)
            4'd0: begin
                if (send_trig) begin
                    snd_data  <= orig_data;   // send ORIGINAL correct byte
                    snd_bit   <= 4'd7;
                    snd_state <= 4'd1;
                end
            end
            4'd1: begin
                if (!tx_busy && !tx_start) begin
                    tx_byte_r <= snd_data[snd_bit] ? 8'h31 : 8'h30;
                    tx_start  <= 1'b1;
                    if (snd_bit == 4'd0) snd_state <= 4'd2;
                    else snd_bit <= snd_bit - 1'b1;
                end
            end
            4'd2: begin  // CR
                if (!tx_busy && !tx_start) begin
                    tx_byte_r <= 8'h0D;
                    tx_start  <= 1'b1;
                    snd_state <= 4'd3;
                end
            end
            4'd3: begin  // LF
                if (!tx_busy && !tx_start) begin
                    tx_byte_r <= 8'h0A;
                    tx_start  <= 1'b1;
                    snd_state <= 4'd0;
                end
            end
            default: snd_state <= 4'd0;
        endcase
    end
end

endmodule
