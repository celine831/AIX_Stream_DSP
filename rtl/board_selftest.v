// EBF EP4CE10 board: 50 MHz E1, reset M15, four active-low LEDs.
// This is a synthesizable BIST, not a replacement for the reusable AXIS core.
module board_selftest #(parameter HEARTBEAT_WIDTH=25, WATCHDOG_CYCLES=50000000)(
    input wire sys_clk, input wire sys_rst_n, output wire [3:0] led);
    localparam BOOT=0,PAUSE=1,WRITE=2,COMMIT=3,RELEASE=4,RUN=5,DRAIN=6,DONE=7;
    reg [7:0] power_on_count=8'd0;
    always @(posedge sys_clk)
        if(power_on_count!=8'hff) power_on_count<=power_on_count+1'b1;
    wire reset_request_n=sys_rst_n && (&power_on_count);
    wire rst_n;
    reset_sync control_reset(sys_clk,reset_request_n,rst_n);
    reg [2:0] state;
    reg [1:0] bank;
    reg [2:0] coeff_index;
    reg [6:0] sent_count,received_count;
    reg [3:0] wait_count;
    reg failed;
    reg [HEARTBEAT_WIDTH-1:0] heartbeat;
    reg [31:0] watchdog;
    reg [7:0] stall_pattern;
    wire done=(state==DONE);
    wire [15:0] input_data,unused_source_expected,reference_expected,unused_reference_sample;
    wire input_last,reference_last;
    board_vector_rom source_rom({bank,sent_count[5:0]},input_data,unused_source_expected,input_last);
    board_vector_rom reference_rom({bank,received_count[5:0]},unused_reference_sample,reference_expected,reference_last);
    wire [15:0] coefficient;
    board_coefficient_rom coefficient_rom({bank,coeff_index},coefficient);
    wire input_valid=(state==RUN) && sent_count<7'd64;
    wire input_ready;
    wire signed [15:0] filtered_data;
    wire filtered_valid,filtered_last;
    // Long and short stalls deliberately exercise FIFO and FIR backpressure on board.
    wire output_ready=(state==RUN || state==DRAIN) && stall_pattern[6:0]>=7'd32 && (stall_pattern[1:0]!=0);
    wire config_pause=(state==BOOT || state==PAUSE || state==WRITE || state==COMMIT);
    wire config_ready,config_error;
    accelerator #(.FRAME_RESET(1),.USE_ASYNC(0)) core(
        .aclk(sys_clk),.s_axis_aclk(sys_clk),.aresetn(reset_request_n),
        .s_axis_tdata(input_data),.s_axis_tvalid(input_valid),.s_axis_tlast(input_last),.s_axis_tready(input_ready),
        .m_axis_tdata(filtered_data),.m_axis_tvalid(filtered_valid),.m_axis_tlast(filtered_last),.m_axis_tready(output_ready),
        .cfg_we(state==WRITE),.cfg_addr(coeff_index),.cfg_data(coefficient),
        .cfg_quiesce(config_pause),.cfg_commit(state==COMMIT),.cfg_ready(config_ready),.cfg_error(config_error));
    always @(posedge sys_clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=BOOT;bank<=0;coeff_index<=0;sent_count<=0;received_count<=0;
            wait_count<=0;failed<=0;heartbeat<=0;watchdog<=0;stall_pattern<=0;
        end else begin
            heartbeat<=heartbeat+1'b1;
            stall_pattern<=stall_pattern+1'b1;
            if(!done) watchdog<=watchdog+1'b1;
            if(config_error) failed<=1;
            if((state==RUN || state==DRAIN) && filtered_valid && output_ready) begin
                if(received_count>=64 || filtered_data!=reference_expected || filtered_last!=reference_last)
                    failed<=1;
                received_count<=received_count+1'b1;
            end
            case(state)
                BOOT: if(wait_count==15) begin wait_count<=0;state<=PAUSE;end
                      else wait_count<=wait_count+1'b1;
                PAUSE: if(config_ready) begin
                    sent_count<=0;received_count<=0;coeff_index<=0;state<=WRITE;
                end
                WRITE: if(coeff_index==7) state<=COMMIT;
                       else coeff_index<=coeff_index+1'b1;
                COMMIT: begin state<=RELEASE;wait_count<=0;end
                RELEASE: if(wait_count==7) state<=RUN;
                         else wait_count<=wait_count+1'b1;
                RUN: if(input_valid && input_ready) begin
                    sent_count<=sent_count+1'b1;
                    if(sent_count==63) state<=DRAIN;
                end
                DRAIN: if(received_count==64) begin
                    if(bank==3) state<=DONE;
                    else begin bank<=bank+1'b1;state<=PAUSE;watchdog<=0;end
                end
                DONE: state<=DONE;
                default: begin state<=DONE;failed<=1;end
            endcase
            if(!done && watchdog>=WATCHDOG_CYCLES-1) begin state<=DONE;failed<=1;end
        end
    end
    // LED1 heartbeat, LED2 PASS, LED3 FAIL, LED4 RUN; all are active-low.
    assign led[0]=~heartbeat[HEARTBEAT_WIDTH-1];
    assign led[1]=~(done && !failed);
    assign led[2]=~failed;
    assign led[3]=~(rst_n && !done);
endmodule
