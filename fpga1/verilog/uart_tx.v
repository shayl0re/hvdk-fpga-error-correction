// ============================================================================
// uart_tx.v  -  UART Transmitter  (FINAL)
//
// 8N1, no flow control
// tx_start: single-clock pulse to begin transmission
// tx_busy:  high while transmitting (do not assert tx_start)
// ============================================================================
module uart_tx #(
    parameter BAUD_DIV = 10416   // CLK_HZ / BAUD_RATE
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       tx_start,
    input  wire [7:0] tx_byte,
    output reg        tx,
    output reg        tx_busy
);

localparam [1:0]
    ST_IDLE  = 2'd0,
    ST_START = 2'd1,
    ST_DATA  = 2'd2,
    ST_STOP  = 2'd3;

reg [1:0]                    state;
reg [$clog2(BAUD_DIV)-1:0]  baud_cnt;
reg [2:0]                    bit_idx;
reg [7:0]                    shift;

always @(posedge clk) begin
    if (rst) begin
        state    <= ST_IDLE;
        tx       <= 1'b1;    // UART idle = high
        tx_busy  <= 1'b0;
        baud_cnt <= 0;
        bit_idx  <= 3'd0;
        shift    <= 8'h00;
    end else begin
        case (state)
            // ----------------------------------------------------------
            ST_IDLE: begin
                tx      <= 1'b1;
                tx_busy <= 1'b0;
                if (tx_start) begin
                    shift    <= tx_byte;
                    baud_cnt <= 0;
                    tx_busy  <= 1'b1;
                    tx       <= 1'b0;   // start bit
                    state    <= ST_START;
                end
            end

            // ----------------------------------------------------------
            ST_START: begin
                if (baud_cnt == BAUD_DIV - 1) begin
                    baud_cnt <= 0;
                    tx       <= shift[0];   // LSB first
                    bit_idx  <= 3'd0;
                    state    <= ST_DATA;
                end else begin
                    baud_cnt <= baud_cnt + 1'b1;
                end
            end

            // ----------------------------------------------------------
            ST_DATA: begin
                if (baud_cnt == BAUD_DIV - 1) begin
                    baud_cnt <= 0;
                    shift    <= {1'b0, shift[7:1]};
                    if (bit_idx == 3'd7) begin
                        tx    <= 1'b1;   // stop bit
                        state <= ST_STOP;
                    end else begin
                        bit_idx <= bit_idx + 1'b1;
                        tx      <= shift[1];   // next bit
                    end
                end else begin
                    baud_cnt <= baud_cnt + 1'b1;
                end
            end

            // ----------------------------------------------------------
            ST_STOP: begin
                if (baud_cnt == BAUD_DIV - 1) begin
                    baud_cnt <= 0;
                    state    <= ST_IDLE;
                    tx_busy  <= 1'b0;
                end else begin
                    baud_cnt <= baud_cnt + 1'b1;
                end
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
