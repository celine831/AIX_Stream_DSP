# Actual board oscillator, 50 MHz, no PLL or fabricated generated clock.
create_clock -name board_clk -period 20.000 [get_ports sys_clk]
derive_clock_uncertainty
# Pushbutton is asynchronous; reset release is synchronized in RTL.
set_input_delay -clock board_clk -max 0.0 [get_ports sys_rst_n]
set_input_delay -clock board_clk -min 0.0 [get_ports sys_rst_n]
set_false_path -from [get_ports sys_rst_n]
# LEDs are human-visible indicators with no synchronous external receiver.
set_output_delay -clock board_clk -max 0.0 [get_ports {led[*]}]
set_output_delay -clock board_clk -min 0.0 [get_ports {led[*]}]
set_false_path -to [get_ports {led[*]}]
