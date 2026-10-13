// Synthesizable Verilog-2001. Testbenches remain SystemVerilog.
// ROUND_MODE: 0=floor (arithmetic truncation), 1=nearest ties away from zero,
// 2=nearest ties to even. SATURATE=0 selects two's-complement wrapping.
module fixed_quantizer #(parameter ACC_WIDTH=35, OUT_WIDTH=16, SHIFT=15,
    ROUND_MODE=1, SATURATE=1)(input wire signed [ACC_WIDTH-1:0] din,
    output reg signed [OUT_WIDTH-1:0] dout);
    reg signed [ACC_WIDTH:0] ext, result, maximum, minimum, bias, half;
    always @* begin
        ext={din[ACC_WIDTH-1],din};
        half=0;
        if(SHIFT>0) half=({{ACC_WIDTH{1'b0}},1'b1} << (SHIFT-1));
        bias=0;
        if(SHIFT>0 && ROUND_MODE!=0) begin
            if(ROUND_MODE==1) bias=ext<0 ? half-1'b1 : half;
            else bias=half-1'b1+((ext>>>SHIFT)&1'b1);
        end
        // Signed bias + arithmetic shift avoids absolute-value and two negations.
        result=(ext+bias)>>>SHIFT;
        maximum=({{ACC_WIDTH{1'b0}},1'b1} << (OUT_WIDTH-1))-1'b1;
        minimum=-({{ACC_WIDTH{1'b0}},1'b1} << (OUT_WIDTH-1));
        if(SATURATE && result>maximum) dout=maximum[OUT_WIDTH-1:0];
        else if(SATURATE && result<minimum) dout=minimum[OUT_WIDTH-1:0];
        else dout=result[OUT_WIDTH-1:0];
    end
endmodule
