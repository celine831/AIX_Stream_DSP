// Synthesizable Verilog-2001. Testbenches remain SystemVerilog.
// Single-clock first-word-fall-through FIFO. Depth must be a power of two >= 2.
module axis_fifo #(parameter WIDTH=17, parameter ADDR_WIDTH=4)(
    input wire clk, rst_n,
    input wire [WIDTH-1:0] s_data, input wire s_valid, output wire s_ready,
    output wire [WIDTH-1:0] m_data, output wire m_valid, input wire m_ready);
    localparam DEPTH=1<<ADDR_WIDTH;
    // Shallow FIFO: registers avoid M9K asynchronous read and bypass critical paths.
    (* ramstyle = "logic" *) reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr, rd_ptr;
    reg [ADDR_WIDTH:0] count;
    wire pop=m_valid && m_ready;
    wire push=s_valid && s_ready;
    assign m_valid=rst_n && (count!=0);
    assign s_ready=rst_n && ((count<DEPTH) || pop);
    assign m_data=mem[rd_ptr];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin wr_ptr<=0; rd_ptr<=0; count<=0; end
        else begin
            if(push) begin mem[wr_ptr]<=s_data; wr_ptr<=wr_ptr+1'b1; end
            if(pop) rd_ptr<=rd_ptr+1'b1;
            case ({push,pop})
                2'b10: count<=count+1'b1;
                2'b01: count<=count-1'b1;
                default: count<=count;
            endcase
        end
    end
endmodule
