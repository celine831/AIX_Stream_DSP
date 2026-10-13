create_clock -name core_clk -period 13.333 [get_ports aclk]
create_clock -name source_clk -period 20.000 [get_ports s_axis_aclk]
derive_clock_uncertainty
set_input_delay -clock source_clk -max 2.0 [get_ports {s_axis_tdata* s_axis_tvalid s_axis_tlast}]
set_input_delay -clock source_clk -min 0.0 [get_ports {s_axis_tdata* s_axis_tvalid s_axis_tlast}]
set_output_delay -clock source_clk -max 2.0 [get_ports s_axis_tready]
set_output_delay -clock source_clk -min 0.0 [get_ports s_axis_tready]
set_input_delay -clock core_clk -max 2.0 [get_ports {m_axis_tready cfg_we cfg_addr* cfg_data* cfg_quiesce cfg_commit}]
set_input_delay -clock core_clk -min 0.0 [get_ports {m_axis_tready cfg_we cfg_addr* cfg_data* cfg_quiesce cfg_commit}]
set_output_delay -clock core_clk -max 2.0 [get_ports {m_axis_tdata* m_axis_tvalid m_axis_tlast cfg_ready cfg_error}]
set_output_delay -clock core_clk -min 0.0 [get_ports {m_axis_tdata* m_axis_tvalid m_axis_tlast cfg_ready cfg_error}]
set_false_path -from [get_ports aresetn]
# No blanket asynchronous clock-group cut: preserve a physical bound on Gray buses.
set_max_delay 10.0 -from [get_registers {*cdc*input_fifo*wr_gray[*]}] -to [get_registers {*cdc*input_fifo*wr_gray_m1[*]}]
set_max_delay 14.0 -from [get_registers {*cdc*input_fifo*rd_gray[*]}] -to [get_registers {*cdc*input_fifo*rd_gray_s1[*]}]
set_min_delay -100.0 -from [get_registers {*cdc*input_fifo*wr_gray[*]}] -to [get_registers {*cdc*input_fifo*wr_gray_m1[*]}]
set_min_delay -100.0 -from [get_registers {*cdc*input_fifo*rd_gray[*]}] -to [get_registers {*cdc*input_fifo*rd_gray_s1[*]}]
set_false_path -to [get_registers {*cdc*pause_s1 *cdc*ack_m1}]
# Payload is stable in storage before the synchronized write pointer enables reading.
set_false_path -from [get_registers {*cdc*input_fifo*mem*}] -to [get_registers {*input_stage*payload*}]

set_max_skew -exclude {from_clock to_clock clock_uncertainty} 10.0 -from [get_registers {*cdc*input_fifo*wr_gray[*]}] -to [get_registers {*cdc*input_fifo*wr_gray_m1[*]}]
set_max_skew -exclude {from_clock to_clock clock_uncertainty} 10.0 -from [get_registers {*cdc*input_fifo*rd_gray[*]}] -to [get_registers {*cdc*input_fifo*rd_gray_s1[*]}]

set_input_delay -clock core_clk -max 0.0 [get_ports aresetn]
set_input_delay -clock core_clk -min 0.0 [get_ports aresetn]

