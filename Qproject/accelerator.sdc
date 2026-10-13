# Core benchmark: 75 MHz. External I/O timing budgets are assumptions, not a board pinout.
create_clock -name core_clk -period 13.333 [get_ports aclk]
derive_clock_uncertainty
set_input_delay -clock core_clk -max 2.0 [get_ports {s_axis_tdata* s_axis_tvalid s_axis_tlast m_axis_tready cfg_we cfg_addr* cfg_data* cfg_quiesce cfg_commit}]
set_input_delay -clock core_clk -min 0.0 [get_ports {s_axis_tdata* s_axis_tvalid s_axis_tlast m_axis_tready cfg_we cfg_addr* cfg_data* cfg_quiesce cfg_commit}]
set_output_delay -clock core_clk -max 2.0 [get_ports {s_axis_tready m_axis_tdata* m_axis_tvalid m_axis_tlast cfg_ready cfg_error}]
set_output_delay -clock core_clk -min 0.0 [get_ports {s_axis_tready m_axis_tdata* m_axis_tvalid m_axis_tlast cfg_ready cfg_error}]
set_false_path -from [get_ports aresetn]

set_input_delay -clock core_clk -max 0.0 [get_ports aresetn]
set_input_delay -clock core_clk -min 0.0 [get_ports aresetn]

