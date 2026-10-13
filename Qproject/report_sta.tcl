package require ::quartus::project
package require ::quartus::sta
set rev [lindex $quartus(args) 0]
if {$rev eq ""} {set rev accelerator}
project_open accelerator -revision $rev
create_timing_netlist
read_sdc
update_timing_netlist
file mkdir reports
report_clocks -file reports/${rev}_clocks.txt
report_clock_fmax_summary -file reports/${rev}_fmax.txt
report_timing -setup -npaths 10 -detail full_path -file reports/${rev}_setup.txt
report_timing -hold -npaths 10 -detail full_path -file reports/${rev}_hold.txt
report_timing -recovery -npaths 5 -detail full_path -file reports/${rev}_recovery.txt
report_timing -removal -npaths 5 -detail full_path -file reports/${rev}_removal.txt
report_ucp -file reports/${rev}_unconstrained.txt
if {$rev eq "accelerator_cdc"} {
    report_max_skew -npaths 10 -detail full_path -file reports/${rev}_gray_skew.txt
}
check_timing -include {no_clock multiple_clock no_input_delay no_output_delay} -file reports/${rev}_check_timing.txt
delete_timing_netlist
project_close
