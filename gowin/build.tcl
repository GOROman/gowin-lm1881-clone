# gw_sh gowin/build.tcl  (リポジトリルートで実行)
set_device GW1NR-LV9QN88PC6/I5 -device_version C
add_file rtl/sync_separator.v
add_file rtl/slice_agc.v
add_file rtl/top_tang_nano_9k.v
add_file constr/tang_nano_9k.cst
add_file constr/tang_nano_9k.sdc
set_option -top_module top_tang_nano_9k
set_option -verilog_std v2001
set_option -output_base_name lm1881_clone
set_option -use_mspi_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_done_as_gpio 1
run all
