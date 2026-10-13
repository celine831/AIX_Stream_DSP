`timescale 1ns/1ps
module tb_quantizer;
    parameter SHIFT=3;
    reg signed [11:0] din;
    wire signed [5:0] dout[0:5];
    genvar i;
    generate for(i=0;i<6;i=i+1) begin:q
        fixed_quantizer #(12,6,SHIFT,i/2,i%2) dut(din,dout[i]);
    end endgenerate
    integer x,j,mag,qval,remv,expectv,divisor;
    initial begin
        divisor=1<<SHIFT;
        for(x=-2048;x<2048;x=x+1) begin
            din=x; #1;
            for(j=0;j<6;j=j+1) begin
                if(j/2==0) begin
                    expectv=x/divisor;
                    if(x<0 && x%divisor!=0) expectv=expectv-1;
                end else begin
                    mag=x<0?-x:x; qval=mag/divisor; remv=mag%divisor;
                    if(SHIFT>0 && (2*remv>divisor || (2*remv==divisor && (j/2==1 || qval%2)))) qval=qval+1;
                    expectv=x<0?-qval:qval;
                end
                if(j%2) begin if(expectv>31) expectv=31; if(expectv< -32) expectv=-32; end
                if(dout[j]!==expectv[5:0]) $fatal(1,"Quantizer x=%0d mode=%0d shift=%0d got=%0d expected=%0d",x,j,SHIFT,dout[j],expectv);
            end
        end
        $display("PASS quantizer shift=%0d comparisons=24576",SHIFT); $finish;
    end
endmodule
