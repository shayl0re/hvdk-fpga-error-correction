module uart_tx2 #(parameter BAUD_DIV = 10416) (
    input  wire       clk,
    input  wire       rst,
    input  wire       tx_start,
    input  wire [7:0] tx_byte,
    output reg        tx,
    output reg        tx_busy
);
    localparam S_IDLE=2'd0, S_START=2'd1, S_DATA=2'd2, S_STOP=2'd3;
    reg [1:0]  state;
    reg [13:0] cnt;
    reg [2:0]  bidx;
    reg [7:0]  shreg;

    always @(posedge clk) begin
        if (rst) begin
            state<=S_IDLE; tx<=1; tx_busy<=0; cnt<=0; bidx<=0; shreg<=0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx<=1; tx_busy<=0;
                    if (tx_start) begin
                        shreg<=tx_byte; tx_busy<=1;
                        tx<=0; cnt<=0; state<=S_START;
                    end
                end
                S_START: if (cnt==BAUD_DIV-1) begin
                             cnt<=0; bidx<=0; tx<=shreg[0]; state<=S_DATA;
                         end else cnt<=cnt+1;
                S_DATA:  if (cnt==BAUD_DIV-1) begin
                             cnt<=0;
                             if (bidx==7) begin tx<=1; state<=S_STOP; end
                             else begin bidx<=bidx+1; tx<=shreg[bidx+1]; end
                         end else cnt<=cnt+1;
                S_STOP:  if (cnt==BAUD_DIV-1) begin
                             cnt<=0; state<=S_IDLE;
                         end else cnt<=cnt+1;
            endcase
        end
    end
endmodule
