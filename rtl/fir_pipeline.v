// Synthesizable Verilog-2001. Testbenches remain SystemVerilog.
module fir_pipeline #(parameter DATA_WIDTH=16, COEFF_WIDTH=16, OUT_WIDTH=16,
    TAPS=8, SHIFT=15, ROUND_MODE=1, SATURATE=1, FRAME_RESET=0,
    COEFF_ADDR_WIDTH=(TAPS<=1 ? 1 : clog2(TAPS)))(
    input wire clk, rst_n,
    input wire signed [DATA_WIDTH-1:0] s_data, input wire s_last, s_valid,
    output wire s_ready, output wire signed [OUT_WIDTH-1:0] m_data,
    output wire m_last, m_valid, input wire m_ready,
    input wire cfg_we, input wire [COEFF_ADDR_WIDTH-1:0] cfg_addr,
    input wire signed [COEFF_WIDTH-1:0] cfg_data, input wire commit,
    output wire busy);
    function integer clog2;
        input integer value;
        integer temp;
        begin
            temp=value-1;
            clog2=0;
            while(temp>0) begin clog2=clog2+1; temp=temp>>1; end
        end
    endfunction

    localparam LEVELS=(TAPS<=1 ? 0 : clog2(TAPS));
    localparam LEAVES=1<<LEVELS;
    localparam PROD_WIDTH=DATA_WIDTH+COEFF_WIDTH;
    localparam ACC_WIDTH=PROD_WIDTH+LEVELS;
    reg signed [COEFF_WIDTH-1:0] active [0:TAPS-1], shadow [0:TAPS-1];
    reg signed [DATA_WIDTH-1:0] history [0:TAPS-1];
    reg signed [ACC_WIDTH-1:0] tree [0:(LEVELS+1)*LEAVES-1];
    reg [LEVELS+1:0] valid_pipe, last_pipe;
    reg signed [OUT_WIDTH-1:0] output_data;
    wire advance=!valid_pipe[LEVELS+1] || m_ready;
    wire accept=s_valid && s_ready;
    wire signed [OUT_WIDTH-1:0] quantized;
    assign s_ready=rst_n && advance && !commit;
    assign m_data=output_data;
    assign m_valid=rst_n && valid_pipe[LEVELS+1];
    assign m_last=last_pipe[LEVELS+1];
    assign busy=|valid_pipe;
    fixed_quantizer #(ACC_WIDTH,OUT_WIDTH,SHIFT,ROUND_MODE,SATURATE) quant(
        .din(tree[LEVELS*LEAVES]),.dout(quantized));
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_pipe<=0; last_pipe<=0; output_data<=0;
            for(i=0;i<TAPS;i=i+1) begin active[i]<=0; shadow[i]<=0; history[i]<=0; end
        end else begin
            if(cfg_we && cfg_addr<TAPS) shadow[cfg_addr]<=cfg_data;
            if(commit) begin
                for(i=0;i<TAPS;i=i+1) begin active[i]<=shadow[i]; history[i]<=0; end
            end
            if(advance) begin
                valid_pipe<={valid_pipe[LEVELS:0],accept};
                last_pipe<={last_pipe[LEVELS:0],s_last && accept};
                if(valid_pipe[LEVELS]) output_data<=quantized;
                if(accept) begin
                    if(FRAME_RESET && s_last) for(i=0;i<TAPS;i=i+1) history[i]<=0;
                    else begin
                        history[0]<=s_data;
                        for(i=1;i<TAPS;i=i+1) history[i]<=history[i-1];
                    end
                end
            end
        end
    end
    genvar k,l;
    generate for(k=0;k<LEAVES;k=k+1) begin: products
        if(k<TAPS) begin: used
            wire signed [DATA_WIDTH-1:0] sample;
            wire signed [PROD_WIDTH-1:0] product;
            if(k==0) assign sample=s_data;
            else assign sample=history[k-1];
            assign product=sample*active[k];
            always @(posedge clk) if(advance && accept)
                tree[k]<={{LEVELS{product[PROD_WIDTH-1]}},product};
        end else begin: padding
            always @(posedge clk) if(advance) tree[k]<=0;
        end
    end
    for(l=1;l<=LEVELS;l=l+1) begin: levels
        for(k=0;k<(LEAVES>>l);k=k+1) begin: nodes
            always @(posedge clk) if(advance && valid_pipe[l-1])
                tree[l*LEAVES+k]<=tree[(l-1)*LEAVES+2*k]+tree[(l-1)*LEAVES+2*k+1];
        end
    end endgenerate
endmodule
