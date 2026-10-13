add wave -divider AXI_input
add wave sim:/tb_accelerator/sclk sim:/tb_accelerator/svalid sim:/tb_accelerator/sready sim:/tb_accelerator/sdata sim:/tb_accelerator/slast
add wave -divider AXI_output
add wave sim:/tb_accelerator/aclk sim:/tb_accelerator/mvalid sim:/tb_accelerator/mready sim:/tb_accelerator/mdata sim:/tb_accelerator/mlast
add wave -divider Configuration
add wave sim:/tb_accelerator/cfg_quiesce sim:/tb_accelerator/cfg_ready sim:/tb_accelerator/cfg_commit sim:/tb_accelerator/cfg_error
add wave -divider Pipeline
add wave sim:/tb_accelerator/dut/fir/valid_pipe sim:/tb_accelerator/dut/fir/advance
configure wave -namecolwidth 250
wave zoom full
