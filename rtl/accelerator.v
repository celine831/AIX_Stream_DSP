// Synthesizable Verilog-2001. Testbenches remain SystemVerilog.
// Core and output use aclk. Source uses s_axis_aclk only when USE_ASYNC=1.
// Configuration is synchronous to aclk. Hold cfg_quiesce until commit completes.
module accelerator #(parameter DATA_WIDTH=16, COEFF_WIDTH=16, OUT_WIDTH=16,
    TAPS=8, SHIFT=15, ROUND_MODE=1, SATURATE=1, FRAME_RESET=0,
    FIFO_ADDR_WIDTH=4, USE_ASYNC=0,
    COEFF_ADDR_WIDTH=(TAPS<=1 ? 1 : clog2(TAPS)))(
    input wire aclk, s_axis_aclk, aresetn,
    input wire signed [8*((DATA_WIDTH+7)/8)-1:0] s_axis_tdata,
    input wire s_axis_tvalid, s_axis_tlast, output wire s_axis_tready,
    output wire signed [8*((OUT_WIDTH+7)/8)-1:0] m_axis_tdata,
    output wire m_axis_tvalid, m_axis_tlast, input wire m_axis_tready,
    input wire cfg_we, input wire [COEFF_ADDR_WIDTH-1:0] cfg_addr,
    input wire signed [COEFF_WIDTH-1:0] cfg_data,
    input wire cfg_quiesce, cfg_commit, output wire cfg_ready, cfg_error);
    function integer clog2;
        input integer value;
        integer temp;
        begin
            temp=value-1;
            clog2=0;
            while(temp>0) begin clog2=clog2+1; temp=temp>>1; end
        end
    endfunction

    localparam AXIS_OUT_WIDTH=8*((OUT_WIDTH+7)/8);
    // synthesis translate_off
    initial begin
        if(DATA_WIDTH<1 || DATA_WIDTH>32 || COEFF_WIDTH<1 || COEFF_WIDTH>32 ||
           TAPS<1 || TAPS>64 || OUT_WIDTH<1 || OUT_WIDTH>DATA_WIDTH+COEFF_WIDTH+clog2(TAPS) ||
           SHIFT<0 || SHIFT>=DATA_WIDTH+COEFF_WIDTH+clog2(TAPS) ||
           ROUND_MODE<0 || ROUND_MODE>2 || FIFO_ADDR_WIDTH<2 || FIFO_ADDR_WIDTH>8 ||
           (USE_ASYNC!=0 && USE_ASYNC!=1) || (SATURATE!=0 && SATURATE!=1) ||
           (FRAME_RESET!=0 && FRAME_RESET!=1) || COEFF_ADDR_WIDTH<(TAPS<=1?1:clog2(TAPS)))
            begin $display("ERROR: Unsupported accelerator parameters"); $finish; end
    end
    // synthesis translate_on
    wire rst_n;
    reset_sync core_reset(aclk,aresetn,rst_n);
    wire [DATA_WIDTH:0] in_payload;
    wire in_valid,in_ready,fifo_ready,paused;
    wire pause_ack;
    // Wait for pointer synchronization AND the registered empty flag after pause ack.
    reg [2:0] pause_settled;
    always @(posedge aclk or negedge rst_n)
        if(!rst_n) pause_settled<=0;
        else if(!cfg_quiesce) pause_settled<=0;
        else pause_settled<={pause_settled[1:0],pause_ack};
    generate if(USE_ASYNC) begin: cdc
        wire source_rst_n;
        reset_sync source_reset(s_axis_aclk,aresetn,source_rst_n);
        (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg pause_s1,pause_s2,ack_m1,ack_m2;
        always @(posedge s_axis_aclk or negedge source_rst_n)
            if(!source_rst_n) begin pause_s1<=0; pause_s2<=0; end
            else begin pause_s1<=cfg_quiesce; pause_s2<=pause_s1; end
        always @(posedge aclk or negedge rst_n)
            if(!rst_n) begin ack_m1<=0; ack_m2<=0; end
            else begin ack_m1<=pause_s2; ack_m2<=ack_m1; end
        assign paused=pause_s2;
        assign pause_ack=ack_m2;
        axis_async_fifo #(DATA_WIDTH+1,FIFO_ADDR_WIDTH) input_fifo(
            s_axis_aclk,source_rst_n,{s_axis_tlast,s_axis_tdata[DATA_WIDTH-1:0]},s_axis_tvalid && !paused,fifo_ready,
            aclk,rst_n,in_payload,in_valid,in_ready);
    end else begin: single_clock
        assign paused=cfg_quiesce;
        assign pause_ack=cfg_quiesce;
        axis_fifo #(DATA_WIDTH+1,FIFO_ADDR_WIDTH) input_fifo(
            aclk,rst_n,{s_axis_tlast,s_axis_tdata[DATA_WIDTH-1:0]},s_axis_tvalid && !paused,fifo_ready,
            in_payload,in_valid,in_ready);
    end endgenerate
    assign s_axis_tready=fifo_ready && !paused;
    wire signed [OUT_WIDTH-1:0] fir_data;
    wire fir_last,fir_valid,fir_ready,fir_busy;
    wire do_commit=cfg_commit && cfg_ready;
    wire [DATA_WIDTH:0] registered_input;
    wire registered_valid,registered_ready;
    axis_register #(DATA_WIDTH+1) input_stage(aclk,rst_n,in_payload,in_valid,in_ready,
        registered_input,registered_valid,registered_ready);
    wire output_fifo_valid;
    assign cfg_ready=rst_n && cfg_quiesce && (&pause_settled) && !in_valid && !registered_valid && !fir_busy && !output_fifo_valid && !m_axis_tvalid;
    assign cfg_error=rst_n && ((cfg_we && cfg_addr>=TAPS) || (cfg_commit && !cfg_ready) || (cfg_commit && cfg_we));
    fir_pipeline #(DATA_WIDTH,COEFF_WIDTH,OUT_WIDTH,TAPS,SHIFT,ROUND_MODE,SATURATE,FRAME_RESET,COEFF_ADDR_WIDTH)
        fir(aclk,rst_n,registered_input[DATA_WIDTH-1:0],registered_input[DATA_WIDTH],registered_valid,registered_ready,
        fir_data,fir_last,fir_valid,fir_ready,cfg_we,cfg_addr,cfg_data,do_commit && !cfg_we,fir_busy);
    wire [OUT_WIDTH:0] out_payload;
    wire output_fifo_ready;
    axis_fifo #(OUT_WIDTH+1,FIFO_ADDR_WIDTH) output_fifo(
        aclk,rst_n,{fir_last,fir_data},fir_valid,fir_ready,out_payload,output_fifo_valid,output_fifo_ready);
    wire [OUT_WIDTH:0] registered_output;
    axis_register #(OUT_WIDTH+1) output_stage(aclk,rst_n,out_payload,output_fifo_valid,output_fifo_ready,
        registered_output,m_axis_tvalid,m_axis_tready);
    assign m_axis_tlast=registered_output[OUT_WIDTH];
    assign m_axis_tdata={{(AXIS_OUT_WIDTH-OUT_WIDTH){registered_output[OUT_WIDTH-1]}},registered_output[OUT_WIDTH-1:0]};
endmodule
