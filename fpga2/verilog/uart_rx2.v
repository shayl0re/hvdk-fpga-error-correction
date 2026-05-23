module uart_rx2 #(parameter BAUD_DIV = 10416) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data_out,
    output reg        data_rdy
);
    localparam HALF = BAUD_DIV / 2;
    reg rx0, rx1, rx2;
    always @(posedge clk) begin rx0<=rx; rx1<=rx0; rx2<=rx1; end

    localparam S_IDLE=2'd0, S_START=2'd1, S_DATA=2'd2, S_STOP=2'd3;
    reg [1:0]  state;
    reg [13:0] cnt;
    reg [2:0]  bidx;
    reg [7:0]  shreg;

    always @(posedge clk) begin
        if (rst) begin
            state<=S_IDLE; cnt<=0; bidx<=0; shreg<=0; data_out<=0; data_rdy<=0;
        end else begin
            data_rdy<=0;
            case (state)
                S_IDLE:  if (!rx1 && rx2) begin cnt<=0; state<=S_START; end
                S_START: if (cnt==HALF-1) begin
                             cnt<=0;
                             if (!rx1) begin bidx<=0; state<=S_DATA; end
                             else state<=S_IDLE;
                         end else cnt<=cnt+1;
                S_DATA:  if (cnt==BAUD_DIV-1) begin
                             cnt<=0; shreg<={rx1,shreg[7:1]};
                             if (bidx==7) state<=S_STOP; else bidx<=bidx+1;
                         end else cnt<=cnt+1;
                S_STOP:  if (cnt==BAUD_DIV-1) begin
                             cnt<=0; state<=S_IDLE;
                             if (rx1) begin data_out<=shreg; data_rdy<=1; end
                         end else cnt<=cnt+1;
            endcase
        end
    end
endmodule
