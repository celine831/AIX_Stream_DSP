onerror {quit -code 1 -force}
onbreak {quit -code 1 -force}
if {![file exists work]} {vlib work}
vmap work work
vlog -lint ../rtl/reset_sync.v ../rtl/axis_fifo.v ../rtl/axis_async_fifo.v ../rtl/axis_register.v ../rtl/fixed_quantizer.v ../rtl/fir_pipeline.v ../rtl/accelerator.v
vlog -sv -lint tb_accelerator.sv
vsim -voptargs=+acc work.tb_accelerator +CASE=sync_default
log -r /*
run -all
quit -code 0 -force
