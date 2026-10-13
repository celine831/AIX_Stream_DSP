`timescale 1ns/1ps
module tb_board_selftest;
    reg clk=0,reset_n=0;
    always #10 clk=~clk;
    wire [3:0] led;
    board_selftest #(.HEARTBEAT_WIDTH(8),.WATCHDOG_CYCLES(10000)) dut(clk,reset_n,led);
    integer xs[0:255],ys[0:255],lasts[0:255];
    integer fd,rc,i,sent=0,received=0,stalls=0;
    reg check_numeric=0,prior_stall=0;
    reg [16:0] held;
    always @(posedge clk) if(reset_n && check_numeric && dut.rst_n) begin
        if(dut.input_valid && dut.input_ready) begin
            if(sent>=256 || dut.input_data!==xs[sent][15:0] || dut.input_last!==lasts[sent][0])
                $fatal(1,"Board source mismatch at %0d",sent);
            sent=sent+1;
        end
        if(prior_stall && (!dut.filtered_valid || {dut.filtered_last,dut.filtered_data}!==held))
            $fatal(1,"Board AXIS output changed during stall");
        prior_stall=dut.filtered_valid && !dut.output_ready;
        held={dut.filtered_last,dut.filtered_data};
        if(prior_stall) stalls=stalls+1;
        if(dut.filtered_valid && dut.output_ready) begin
            if(received>=sent || dut.filtered_data!==ys[received][15:0] || dut.filtered_last!==lasts[received][0])
                $fatal(1,"Board golden mismatch at %0d",received);
            received=received+1;
        end
    end else prior_stall=0;
    task start_clean;
        begin
            @(negedge clk);reset_n=0;check_numeric=0;
            repeat(8) @(negedge clk);
            sent=0;received=0;stalls=0;reset_n=1;check_numeric=1;
        end
    endtask
    task expect_pass;
        begin
            wait(dut.done);@(negedge clk);
            if(dut.failed || sent!=256 || received!=256 || stalls==0 || led[3:1]!==3'b110)
                $fatal(1,"Board PASS check failed sent=%0d received=%0d LED=%b",sent,received,led);
            $display("Board numeric PASS sent=%0d received=%0d stalls=%0d",sent,received,stalls);
        end
    endtask
    reg heartbeat_before;
    initial begin
        fd=$fopen("vectors/board_data.txt","r");if(!fd) $fatal(1,"Missing board vectors");
        for(i=0;i<256;i=i+1) begin rc=$fscanf(fd,"%d %d %d\n",xs[i],ys[i],lasts[i]);if(rc!=3) $fatal(1,"Bad board vector");end
        $fclose(fd);
        start_clean();expect_pass();
        heartbeat_before=led[0];repeat(128) @(negedge clk);
        if(led[0]===heartbeat_before) $fatal(1,"Heartbeat stopped");
        start_clean();expect_pass();
        // Corrupt one result to prove FAIL does not masquerade as PASS.
        start_clean();check_numeric=0;
        wait(dut.filtered_valid && dut.output_ready);@(negedge clk);
        while(!dut.output_ready) @(negedge clk);
        force dut.filtered_data=~dut.reference_expected;
        @(posedge clk);@(negedge clk);release dut.filtered_data;
        wait(dut.done);@(negedge clk);
        if(!dut.failed || led[3:1]!==3'b101) $fatal(1,"Fault was not latched into FAIL LED");
        $display("PASS board_selftest 512 golden comparisons reset rerun heartbeat and injected mismatch");$finish;
    end
    initial begin #2000000;$fatal(1,"Board test timeout");end
endmodule
