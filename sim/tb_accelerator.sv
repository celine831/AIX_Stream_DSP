`timescale 1ns/1ps
module tb_accelerator;
    parameter DATA_WIDTH=16,COEFF_WIDTH=16,OUT_WIDTH=16,TAPS=8,SHIFT=15;
    parameter ROUND_MODE=1,SATURATE=1,FRAME_RESET=0,USE_ASYNC=0,FIFO_ADDR_WIDTH=4;
    parameter SOURCE_HALF_PERIOD=7;
    localparam CAW=TAPS<=1?1:$clog2(TAPS);
    localparam AXDW=8*((DATA_WIDTH+7)/8),AXOW=8*((OUT_WIDTH+7)/8);
    reg aclk=0, source_clock=0, aresetn=0;
    always #5 aclk=~aclk;
    always #(SOURCE_HALF_PERIOD) source_clock=~source_clock;
    wire sclk=USE_ASYNC ? source_clock : aclk;
    reg signed [AXDW-1:0] sdata=0;
    reg svalid=0,slast=0,mready=0;
    wire sready,mvalid,mlast;
    wire signed [AXOW-1:0] mdata;
    reg cfg_we=0,cfg_quiesce=0,cfg_commit=0;
    reg [CAW-1:0] cfg_addr=0;
    reg signed [COEFF_WIDTH-1:0] cfg_data=0;
    wire cfg_ready,cfg_error;
    accelerator #(DATA_WIDTH,COEFF_WIDTH,OUT_WIDTH,TAPS,SHIFT,ROUND_MODE,SATURATE,FRAME_RESET,
        FIFO_ADDR_WIDTH,USE_ASYNC) dut(aclk,sclk,aresetn,sdata,svalid,slast,sready,
        mdata,mvalid,mlast,mready,cfg_we,cfg_addr,cfg_data,cfg_quiesce,cfg_commit,cfg_ready,cfg_error);
    integer x[0:1535],expected[0:1535],last[0:1535];
    integer cs[0:3*TAPS-1];
    integer received=0,sent=0,cycles=0,stalls=0,input_stalls=0,continuous=0,max_continuous=0;
    time first_input_time=0,first_output_time=0;
    integer fd,rc,i,j,phase,seed=20261013;
    reg checking=0,force_stall=0,hold_check=0;
    reg [AXOW:0] held;
    reg source_hold=0;
    reg [AXDW:0] held_source;
    reg [31:0] lfsr=32'h12345678;
    reg [511:0] case_name;
    reg [1023:0] filename;
    always @(negedge aclk) begin
        lfsr={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
        if(!aresetn || force_stall) mready<=0;
        else if(checking && received<256) mready<=1;
        else if(checking && (cycles%160)<80) mready<=0;
        else mready<=lfsr[0] || lfsr[3];
    end
    always @(posedge aclk) begin
        cycles=cycles+1;
        if(!aresetn) hold_check=0;
        else begin
            if(hold_check && (!mvalid || {mlast,mdata}!==held))
                $fatal(1,"AXIS payload changed while stalled");
            hold_check=mvalid && !mready;
            held={mlast,mdata};
            if(checking && mvalid && !mready) stalls=stalls+1;
            if(checking && mvalid && mready) begin
                if(received==0) first_output_time=$time;
                if(received>=sent) $fatal(1,"Unaccepted or duplicate output at %0d",received);
                if(mdata!==$signed(expected[received][AXOW-1:0]) || mlast!==last[received][0])
                    $fatal(1,"Mismatch n=%0d got=%0d expected=%0d last=%b/%b",received,mdata,expected[received],mlast,last[received][0]);
                received=received+1;
                continuous=continuous+1;
                if(continuous>max_continuous) max_continuous=continuous;
            end else continuous=0;
        end
    end
    // Score input acceptance independently of the driver; reset aborts transactions.
    always @(posedge sclk) if(aresetn && checking) begin
        if(source_hold && (!svalid || {slast,sdata}!==held_source))
            $fatal(1,"Source violated AXIS stability while stalled");
        source_hold=svalid && !sready;
        held_source={slast,sdata};
        if(svalid && sready) begin
            if(sent==0) first_input_time=$time;
            sent=sent+1;
        end
        if(svalid && !sready) input_stalls=input_stalls+1;
    end else source_hold=0;
    generate if(USE_ASYNC) begin: gray_checks
        reg [FIFO_ADDR_WIDTH:0] prev_wr=0,prev_rd=0;
        always @(posedge sclk) begin
            if(!dut.cdc.source_rst_n) prev_wr=0;
            else begin
                if(!$onehot0(prev_wr ^ dut.cdc.input_fifo.wr_gray)) $fatal(1,"Write Gray pointer changed multiple bits");
                prev_wr=dut.cdc.input_fifo.wr_gray;
            end
        end
        always @(posedge aclk) begin
            if(!dut.rst_n) prev_rd=0;
            else begin
                if(!$onehot0(prev_rd ^ dut.cdc.input_fifo.rd_gray)) $fatal(1,"Read Gray pointer changed multiple bits");
                prev_rd=dut.cdc.input_fifo.rd_gray;
            end
        end
    end endgenerate
    task reset_design;
        begin
            aresetn=0; svalid=0; cfg_we=0; cfg_commit=0; cfg_quiesce=0;
            repeat(5) @(negedge aclk);
            aresetn=1;
            repeat(10) @(negedge aclk);
        end
    endtask
    task configure(input integer bank);
        begin
            @(negedge aclk); cfg_quiesce=1;
            wait(cfg_ready); @(negedge aclk);
            if((1<<CAW)>TAPS) begin
                cfg_we=1; cfg_addr=(1<<CAW)-1; cfg_data=0;
                #1; if(!cfg_error) $fatal(1,"Invalid coefficient address not rejected");
                @(negedge aclk); cfg_we=0;
            end
            for(j=0;j<TAPS;j=j+1) begin
                cfg_we=1; cfg_addr=j; cfg_data=cs[bank*TAPS+j];
                @(negedge aclk);
            end
            cfg_we=0; cfg_commit=1;
            #1; if(cfg_error) $fatal(1,"Legal coefficient commit rejected");
            @(negedge aclk); cfg_commit=0; cfg_quiesce=0;
            repeat(10) @(negedge aclk);
        end
    endtask
    initial begin
        if(!$value$plusargs("CASE=%s",case_name)) case_name="sync_default";
        $sformat(filename,"vectors/%0s_data.txt",case_name);
        fd=$fopen(filename,"r"); if(!fd) $fatal(1,"Cannot open vectors");
        for(i=0;i<1536;i=i+1) begin
            rc=$fscanf(fd,"%d %d %d\n",x[i],expected[i],last[i]);
            if(rc!=3) $fatal(1,"Vector parse error");
        end
        $fclose(fd);
        $sformat(filename,"vectors/%0s_coeff.txt",case_name);
        fd=$fopen(filename,"r"); if(!fd) $fatal(1,"Cannot open coefficients");
        for(i=0;i<3*TAPS;i=i+1) begin rc=$fscanf(fd,"%d\n",cs[i]); if(rc!=1) $fatal(1,"Coeff parse error"); end
        $fclose(fd);
        reset_design();
        // Exercise reset with a full FIFO and live, stalled pipeline.
        configure(0); force_stall=1;
        for(i=0;i<80;i=i+1) begin
            @(negedge sclk); svalid=1; sdata=i; slast=(i==79);
        end
        reset_design(); force_stall=0;
        repeat(30) @(negedge aclk);
        if(mvalid) $fatal(1,"Stale data survived reset");
        // Illegal commit while source is not quiesced must not change active bank.
        cfg_commit=1; #1; if(!cfg_error) $fatal(1,"Missing configuration error");
        @(negedge aclk); cfg_commit=0;
        checking=1;
        for(phase=0;phase<3;phase=phase+1) begin
            configure(phase);
            for(i=phase*512;i<(phase+1)*512;i=i+1) begin
                @(negedge sclk);
                if(i%512==260) begin
                    svalid=0;
                    @(negedge aclk); cfg_quiesce=1;
                    wait(cfg_ready); @(negedge aclk);
                    if(received!=sent) $fatal(1,"Configuration ready before all accepted data drained");
                    cfg_we=1; cfg_addr=0; cfg_data=cs[phase*TAPS]; cfg_commit=1;
                    #1; if(!cfg_error) $fatal(1,"Simultaneous write and commit not rejected");
                    @(negedge aclk); cfg_we=0; cfg_commit=0; cfg_quiesce=0;
                    repeat(10) @(negedge sclk);
                end
                if(i%512>=256 && i%9==0) begin svalid=0; repeat(2) @(negedge sclk); end
                svalid=1; sdata=x[i]; slast=last[i];
                @(posedge sclk);
                while(!sready) @(posedge sclk);
            end
            @(negedge sclk); svalid=0;
            wait(received==(phase+1)*512);
            repeat(10) @(negedge aclk);
        end
        repeat(100) @(negedge aclk);
        if(received!=1536 || sent!=1536 || stalls==0 || input_stalls==0)
            $fatal(1,"Coverage missing sent=%0d received=%0d stalls=%0d input_stalls=%0d",sent,received,stalls,input_stalls);
        if(!USE_ASYNC && max_continuous<200) $fatal(1,"II=1 throughput check failed");
        if(!USE_ASYNC && first_output_time-first_input_time!=10*($clog2(TAPS)+6))
            $fatal(1,"Unexpected no-stall latency %0t",first_output_time-first_input_time);
        $display("PASS case=%0s sent=%0d received=%0d stalls=%0d input_stalls=%0d max_consecutive=%0d cycles=%0d first_latency_ns=%0d",case_name,sent,received,stalls,input_stalls,max_continuous,cycles,first_output_time-first_input_time);
        $finish;
    end
    initial begin #2000000; $fatal(1,"Watchdog timeout sent=%0d received=%0d",sent,received); end
endmodule
