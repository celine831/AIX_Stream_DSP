// Synthesizable Verilog-2001. Testbenches remain SystemVerilog.
// Gray pointers cross through two FFs; payload remains in dual-clock storage.
// Both domains must share the same asynchronous reset assertion.
module axis_async_fifo #(parameter WIDTH=17, parameter ADDR_WIDTH=4)(
    input wire s_clk, s_rst_n, input wire [WIDTH-1:0] s_data,
    input wire s_valid, output wire s_ready,
    input wire m_clk, m_rst_n, output wire [WIDTH-1:0] m_data,
    output wire m_valid, input wire m_ready);
    localparam DEPTH=1<<ADDR_WIDTH;
    (* ramstyle = "logic" *) reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH:0] wr_bin, wr_gray, rd_bin, rd_gray;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg [ADDR_WIDTH:0] rd_gray_s1, rd_gray_s2, wr_gray_m1, wr_gray_m2;
    reg full, empty;
    wire push=s_valid && s_ready, pop=m_valid && m_ready;
    wire [ADDR_WIDTH:0] wr_next=wr_bin+push;
    wire [ADDR_WIDTH:0] rd_next=rd_bin+pop;
    wire [ADDR_WIDTH:0] wg_next=(wr_next>>1)^wr_next;
    wire [ADDR_WIDTH:0] rg_next=(rd_next>>1)^rd_next;
    wire [ADDR_WIDTH:0] full_compare={~rd_gray_s2[ADDR_WIDTH:ADDR_WIDTH-1],rd_gray_s2[ADDR_WIDTH-2:0]};
    assign s_ready=s_rst_n && !full;
    assign m_valid=m_rst_n && !empty;
    assign m_data=mem[rd_bin[ADDR_WIDTH-1:0]];
    always @(posedge s_clk or negedge s_rst_n) begin
        if(!s_rst_n) begin wr_bin<=0; wr_gray<=0; full<=0; rd_gray_s1<=0; rd_gray_s2<=0; end
        else begin
            rd_gray_s1<=rd_gray; rd_gray_s2<=rd_gray_s1;
            wr_bin<=wr_next; wr_gray<=wg_next; full<=(wg_next==full_compare);
            if(push) mem[wr_bin[ADDR_WIDTH-1:0]]<=s_data;
        end
    end
    always @(posedge m_clk or negedge m_rst_n) begin
        if(!m_rst_n) begin rd_bin<=0; rd_gray<=0; empty<=1; wr_gray_m1<=0; wr_gray_m2<=0; end
        else begin
            wr_gray_m1<=wr_gray; wr_gray_m2<=wr_gray_m1;
            rd_bin<=rd_next; rd_gray<=rg_next; empty<=(rg_next==wr_gray_m2);
        end
    end
endmodule
