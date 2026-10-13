// Synthesizable Verilog-2001. Testbenches remain SystemVerilog.
module reset_sync(input wire clk, input wire arst_n, output wire rst_n);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg [1:0] sync_ff;
    always @(posedge clk or negedge arst_n)
        if (!arst_n) sync_ff <= 2'b00;
        else sync_ff <= {sync_ff[0], 1'b1};
    assign rst_n = sync_ff[1];
endmodule
