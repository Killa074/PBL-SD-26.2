# HPS/DDR constraints come from the preserved professor IP and timing SDC.
set_false_path -from [get_ports {KEY[*]}]
# Provisional external DAC delays: physical board signoff remains necessary.
set_output_delay -clock clock_50_1 -max 5.0 [get_ports {VGA_*}]
set_output_delay -clock clock_50_1 -min 0.0 [get_ports {VGA_*}]
