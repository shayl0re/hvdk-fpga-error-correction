// ============================================================================
// uart_rx.v  -  UART Receiver  (FINAL)
//
// 8N1, no flow control
// Oversamples at 16x for robustness against HC-05 / timing variation
// data_rdy is a single-clock pulse when a full byte is received
// ============================================================================
module uart_rx #(
    parameter BAUD_DIV = 10416   // CLK_HZ / BAUD_RATE
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data_out,
    output reg        data_rdy
);

// 16x oversampling: sample clock = BAUD_DIV / 16
localparam SAMPLE_DIV  = BAUD_DIV / 16;       // ticks per sample clock
localparam HALF_BIT    = 8;                    // samples to reach bit centre from start edge
localparam FULL_BIT    = 16;                   // samples per bit

// --------------------------------------------------------------------------
// Input synchroniser (2FF) to avoid metastability
// --------------------------------------------------------------------------
reg rx_s1, rx_s2, rx_s3;
always @(posedge clk) begin
    rx_s1 <= rx;
    rx_s2 <= rx_s1;
    rx_s3 <= rx_s2;
end
wire rx_sync = rx_s2;
wire rx_fall = rx_s3 & ~rx_s2;   // falling edge detector (start bit)

// --------------------------------------------------------------------------
// Sample clock generator
// --------------------------------------------------------------------------
reg [$clog2(SAMPLE_DIV)-1:0] sample_cnt;
reg sample_tick;

always @(posedge clk) begin
    if (rst) begin
        sample_cnt  <= 0;
        sample_tick <= 1'b0;
    end else if (sample_cnt == SAMPLE_DIV - 1) begin
        sample_cnt  <= 0;
        sample_tick <= 1'b1;
    end else begin
        sample_cnt  <= sample_cnt + 1;
        sample_tick <= 1'b0;
    end
end

// --------------------------------------------------------------------------
// FSM
// --------------------------------------------------------------------------
localparam [1:0]
    ST_IDLE  = 2'd0,
    ST_START = 2'd1,
    ST_DATA  = 2'd2,
    ST_STOP  = 2'd3;

reg [1:0]  state;
reg [4:0]  tick_cnt;   // sample counter within current bit
reg [2:0]  bit_idx;    // which data bit we are receiving (0..7)
reg [7:0]  shift;      // shift register

always @(posedge clk) begin
    if (rst) begin
        state    <= ST_IDLE;
        tick_cnt <= 5'd0;
        bit_idx  <= 3'd0;
        shift    <= 8'h00;
        data_out <= 8'h00;
        data_rdy <= 1'b0;
    end else begin
        data_rdy <= 1'b0;

        case (state)
            // ----------------------------------------------------------
            // Wait for falling edge (start bit)
            // ----------------------------------------------------------
            ST_IDLE: begin
                if (rx_fall) begin
                    tick_cnt <= 5'd0;
                    state    <= ST_START;
                end
            end

            // ----------------------------------------------------------
            // Verify start bit at mid-point
            // ----------------------------------------------------------
            ST_START: begin
                if (sample_tick) begin
                    if (tick_cnt == HALF_BIT - 1) begin
                        if (rx_sync == 1'b0) begin
                            // Valid start bit
                            tick_cnt <= 5'd0;
                            bit_idx  <= 3'd0;
                            state    <= ST_DATA;
                        end else begin
                            // Glitch, go back to idle
                            state <= ST_IDLE;
                        end
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end
            end

            // ----------------------------------------------------------
            // Sample 8 data bits at the centre of each bit period
            // ----------------------------------------------------------
            ST_DATA: begin
                if (sample_tick) begin
                    if (tick_cnt == FULL_BIT - 1) begin
                        shift    <= {rx_sync, shift[7:1]};  // LSB first
                        tick_cnt <= 5'd0;
                        if (bit_idx == 3'd7) begin
                            state <= ST_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end
            end

            // ----------------------------------------------------------
            // Stop bit — output the received byte
            // ----------------------------------------------------------
            ST_STOP: begin
                if (sample_tick) begin
                    if (tick_cnt == FULL_BIT - 1) begin
                        data_out <= shift;
                        data_rdy <= 1'b1;
                        state    <= ST_IDLE;
                        tick_cnt <= 5'd0;
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
