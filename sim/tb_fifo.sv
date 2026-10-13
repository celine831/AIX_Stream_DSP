`timescale 1ns/1ps
module tb_fifo;
    reg clk=0,rst_n=0,sv=0,mr=0;
    always #5 clk=~clk;
    reg [7:0] sd=0;
    wire [7:0] md;
    wire sr,mv;
    axis_fifo #(8,2) dut(clk,rst_n,sd,sv,sr,md,mv,mr);
    integer i;
    initial begin
        repeat(2) @(negedge clk); rst_n=1;
        for(i=0;i<4;i=i+1) begin sv=1; sd=i; @(negedge clk); end
        sv=0; #1; if(sr || !mv || md!=0) $fatal(1,"FIFO full failed");
        // Full FIFO accepts a replacement when its old head is popped.
        sv=1; mr=1; sd=4; #1; if(!sr) $fatal(1,"Full replacement rejected");
        @(negedge clk); sv=0;
        for(i=1;i<=4;i=i+1) begin
            #1; if(!mv || md!=i) $fatal(1,"FIFO ordering i=%0d got=%0d",i,md);
            @(negedge clk);
        end
        mr=0; #1; if(mv) $fatal(1,"FIFO empty failed");
        rst_n=0; #1; if(sr || mv) $fatal(1,"Reset gating failed");
        $display("PASS fifo full simultaneous pop push wrap ordering reset"); $finish;
    end
    initial begin #10000; $fatal(1,"FIFO timeout"); end
endmodule
