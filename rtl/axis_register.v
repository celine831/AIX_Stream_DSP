// Synthesizable Verilog-2001. Testbenches remain SystemVerilog.
// One-entry elastic register; ready propagates backwards, payload is registered.
module axis_register #(parameter WIDTH=17)(input wire clk,rst_n,
    input wire [WIDTH-1:0] s_data,input wire s_valid,output wire s_ready,
    output wire [WIDTH-1:0] m_data,output wire m_valid,input wire m_ready);
    reg [WIDTH-1:0] payload;
    reg valid;
    assign s_ready=rst_n && (!valid || m_ready);
    assign m_valid=rst_n && valid;
    assign m_data=payload;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin valid<=0; payload<=0; end
        else if(s_ready) begin valid<=s_valid; if(s_valid) payload<=s_data; end
endmodule
