// ============================================================================
// top_fpga1.v  -  Basys3 FPGA1  (FINAL)
//
// * Receives 8-bit binary string from PC1 PuTTY (UART 9600-8N1)
// * Calculates HVDK parity (P0-P5)
// * Displays data on LD0-LD7, parity on LD8-LD13
// * Animated HVDK parity generation on MAX7219 8x8 matrix (PMOD JB)
// * Forwards raw byte to FPGA2 via PMOD JA pin1 (UART 9600)
// * Echoes binary string back to PC1
// ============================================================================
module top_fpga1 (
    input  wire        clk,        // 100 MHz
    input  wire        rst_btn,    // BTNC active high
    input  wire        pc_rx,      // USB-UART RX from PC
    output wire        pc_tx,      // USB-UART TX to PC
    output wire        fpga2_tx,   // UART TX to FPGA2 via PMOD JA pin1
    output wire [13:0] led,        // LD0-LD7 = data, LD8-LD13 = parity
    output wire        mx_din,     // MAX7219 DIN  -> PMOD JB pin1
    output wire        mx_cs,      // MAX7219 CS   -> PMOD JB pin2
    output wire        mx_clk      // MAX7219 CLK  -> PMOD JB pin3
);

localparam CLK_HZ    = 100_000_000;
localparam BAUD_RATE = 9600;
localparam BAUD_DIV  = CLK_HZ / BAUD_RATE;  // 10416

// --------------------------------------------------------------------------
// Reset synchroniser (2-stage)
// --------------------------------------------------------------------------
reg rst_s1, rst_s2;
always @(posedge clk) begin
    rst_s1 <= rst_btn;
    rst_s2 <= rst_s1;
end
wire rst = rst_s2;

// --------------------------------------------------------------------------
// UART RX from PC
// --------------------------------------------------------------------------
wire [7:0] rx_byte;
wire       rx_done;

uart_rx #(.BAUD_DIV(BAUD_DIV)) u_rx (
    .clk      (clk),
    .rst      (rst),
    .rx       (pc_rx),
    .data_out (rx_byte),
    .data_rdy (rx_done)
);

// --------------------------------------------------------------------------
// 8-character ASCII accumulator
// Collects '0' and '1' characters, builds data_reg on 8th character
// --------------------------------------------------------------------------
reg [7:0] data_reg;
reg [3:0] char_cnt;
reg [7:0] build_reg;
reg       data_valid;

always @(posedge clk) begin
    if (rst) begin
        data_reg  <= 8'h00;
        char_cnt  <= 4'd0;
        build_reg <= 8'h00;
        data_valid <= 1'b0;
    end else begin
        data_valid <= 1'b0;
        if (rx_done) begin
            if (rx_byte == 8'h30 || rx_byte == 8'h31) begin
                // '0' = 0x30, '1' = 0x31
                build_reg <= {build_reg[6:0], (rx_byte == 8'h31) ? 1'b1 : 1'b0};
                if (char_cnt == 4'd7) begin
                    data_reg   <= {build_reg[6:0], (rx_byte == 8'h31) ? 1'b1 : 1'b0};
                    data_valid <= 1'b1;
                    char_cnt   <= 4'd0;
                    build_reg  <= 8'h00;
                end else begin
                    char_cnt <= char_cnt + 1'b1;
                end
            end else begin
                // Non-binary character resets accumulator
                char_cnt  <= 4'd0;
                build_reg <= 8'h00;
            end
        end
    end
end

// --------------------------------------------------------------------------
// HVDK Parity Calculation
// P0 = d0^d1^d2^d3       (right half)
// P1 = d4^d5^d6^d7       (left half)
// P2 = d0^d2^d4^d6       (even indices)
// P3 = d1^d3^d5^d7       (odd indices)
// P4 = d1^d2^d5^d6       (inner pair each half)
// P5 = all 8 bits XOR    (overall parity)
// --------------------------------------------------------------------------
wire p0 = data_reg[0] ^ data_reg[1] ^ data_reg[2] ^ data_reg[3];
wire p1 = data_reg[4] ^ data_reg[5] ^ data_reg[6] ^ data_reg[7];
wire p2 = data_reg[0] ^ data_reg[2] ^ data_reg[4] ^ data_reg[6];
wire p3 = data_reg[1] ^ data_reg[3] ^ data_reg[5] ^ data_reg[7];
wire p4 = data_reg[1] ^ data_reg[2] ^ data_reg[5] ^ data_reg[6];
wire p5 = ^data_reg;

reg [5:0] parity_reg;
always @(posedge clk) begin
    if (rst) parity_reg <= 6'b000000;
    else     parity_reg <= {p5, p4, p3, p2, p1, p0};
end

// LD0-LD7  = data bits
// LD8-LD13 = parity bits P0-P5
assign led[7:0]  = data_reg;
assign led[13:8] = parity_reg;

// --------------------------------------------------------------------------
// UART TX echo back to PC1
// Sends the 8 binary characters followed by CR LF
// --------------------------------------------------------------------------
wire tx_busy_pc;
reg  tx_start_pc;
reg [7:0] tx_byte_pc;

uart_tx #(.BAUD_DIV(BAUD_DIV)) u_tx_pc (
    .clk      (clk),
    .rst      (rst),
    .tx_start (tx_start_pc),
    .tx_byte  (tx_byte_pc),
    .tx       (pc_tx),
    .tx_busy  (tx_busy_pc)
);

reg [3:0] echo_state;
reg [3:0] echo_bit;
reg [7:0] echo_data;

always @(posedge clk) begin
    if (rst) begin
        echo_state  <= 4'd0;
        tx_start_pc <= 1'b0;
        tx_byte_pc  <= 8'h00;
        echo_bit    <= 4'd0;
        echo_data   <= 8'h00;
    end else begin
        tx_start_pc <= 1'b0;
        case (echo_state)
            4'd0: begin
                if (data_valid) begin
                    echo_data  <= data_reg;
                    echo_bit   <= 4'd7;
                    echo_state <= 4'd1;
                end
            end
            4'd1: begin
                if (!tx_busy_pc && !tx_start_pc) begin
                    tx_byte_pc  <= echo_data[echo_bit] ? 8'h31 : 8'h30;
                    tx_start_pc <= 1'b1;
                    if (echo_bit == 4'd0)
                        echo_state <= 4'd2;
                    else
                        echo_bit <= echo_bit - 1'b1;
                end
            end
            4'd2: begin
                if (!tx_busy_pc && !tx_start_pc) begin
                    tx_byte_pc  <= 8'h0D; // CR
                    tx_start_pc <= 1'b1;
                    echo_state  <= 4'd3;
                end
            end
            4'd3: begin
                if (!tx_busy_pc && !tx_start_pc) begin
                    tx_byte_pc  <= 8'h0A; // LF
                    tx_start_pc <= 1'b1;
                    echo_state  <= 4'd0;
                end
            end
        endcase
    end
end

// --------------------------------------------------------------------------
// UART TX to FPGA2 (raw byte forwarding)
// --------------------------------------------------------------------------
wire tx_busy_f2;
reg  tx_start_f2;
reg [7:0] tx_byte_f2;

uart_tx #(.BAUD_DIV(BAUD_DIV)) u_tx_f2 (
    .clk      (clk),
    .rst      (rst),
    .tx_start (tx_start_f2),
    .tx_byte  (tx_byte_f2),
    .tx       (fpga2_tx),
    .tx_busy  (tx_busy_f2)
);

always @(posedge clk) begin
    if (rst) begin
        tx_start_f2 <= 1'b0;
        tx_byte_f2  <= 8'h00;
    end else begin
        tx_start_f2 <= 1'b0;
        if (data_valid && !tx_busy_f2) begin
            tx_byte_f2  <= data_reg;
            tx_start_f2 <= 1'b1;
        end
    end
end

// --------------------------------------------------------------------------
// MAX7219 HVDK Animated Controller
// --------------------------------------------------------------------------
max7219_hvdk u_max (
    .clk       (clk),
    .rst       (rst),
    .data_in   (data_reg),
    .parity_in (parity_reg),
    .update    (data_valid),
    .din       (mx_din),
    .cs_n      (mx_cs),
    .spi_clk   (mx_clk)
);

endmodule
