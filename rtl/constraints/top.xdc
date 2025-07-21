########################################################################################################################
# Clock constraints

create_clock -period 40.000 -name clk_25mhz -waveform {0.000 20.000} [get_ports clk_25mhz]

#150 MHz (6.66 ns period) FMC clock
create_clock -period 6.66 -name fmc_clk -waveform {0.000 3.33} [get_ports fmc_clk]

#create_generated_clock -name clk_crypt -source [get_pins clocks/pll/CLKIN1] -master_clock [get_clocks clk_25mhz] [get_pins clocks/pll/CLKOUT2]
create_generated_clock -name clk_125mhz -source [get_pins clocks/pll/CLKIN1] -master_clock [get_clocks clk_25mhz] [get_pins clocks/pll/CLKOUT0]
create_generated_clock -name clk_250mhz -source [get_pins clocks/pll/CLKIN1] -master_clock [get_clocks clk_25mhz] [get_pins clocks/pll/CLKOUT1]

######################################################
# CDC constraints

set tmp_i_i0 [get_cells -hierarchical -filter { NAME =~  "*sync*" && NAME =~  "*reg_a_ff*" }]
set tmp_i_i1 [get_cells -hierarchical -filter { NAME =~  "*sync*" && NAME =~  "*reg_b*" }]
set tmp_i_i2 [get_cells -hierarchical -filter { NAME =~  "*sync*" && NAME =~  "*tx_a_reg*" }]
set tmp_i_i3 [get_cells -hierarchical -filter { NAME =~  "*sync*" && NAME =~  "*dout1_reg*" }]
set tmp_i_i4 [get_cells -hierarchical -filter { NAME =~  "*sync*" && NAME =~  "*a_ff*" }]
set tmp_i_i5 [get_cells -hierarchical -filter { NAME =~  "*sync*" && NAME =~  "*dout0_reg*" }]
set tmp_i_i6 [get_cells -hierarchical -filter { NAME =~  "*fifomem*" && NAME =~  "*portb_dout_raw_reg*" }]
set tmp_i_i7 [get_cells -hierarchical -filter { NAME =~  "*fifomem*" }]
set tmp_i_i8 [get_cells -hierarchical -filter { NAME =~  "*apb_cdc*" && NAME =~  "*downstream*" }]
set tmp_i_i9 [get_cells -hierarchical -filter { NAME =~  "*apb_cdc*" && NAME =~  "*upstream*" }]
set tmp_i_i10 [get_cells -hierarchical -filter { NAME =~  "*sync_rst*" && NAME =~  "*_reg*"}]

# TODO update comment with what sync this is
set_max_delay -datapath_only -from $tmp_i_i0 -to $tmp_i_i1 4.00
set_bus_skew -from $tmp_i_i0 -to $tmp_i_i1 4.00

# TODO update comment with what sync this is
set_max_delay -datapath_only -from $tmp_i_i2 -to $tmp_i_i3 4.00
set_bus_skew -from $tmp_i_i2 -to $tmp_i_i3 4.00

# TODO update comment with what sync this is
set_max_delay -datapath_only -from $tmp_i_i4 -to $tmp_i_i1 4.00
set_bus_skew -from $tmp_i_i4 -to $tmp_i_i1 4.00

# ThreeStageSynchronizer
set_max_delay -datapath_only -from $tmp_i_i5 -to $tmp_i_i3 4.00
set_bus_skew -from $tmp_i_i5 -to $tmp_i_i3 4.00

# APB_CDC
set_max_delay -datapath_only -from [get_clocks pclk_raw] -to $tmp_i_i8 4.00
set_max_delay -datapath_only -from $tmp_i_i9 -to [get_clocks pclk_raw] 4.00

# Cross clock BRAM FIFOs
set_false_path -from [get_clocks pclk_raw] -through $tmp_i_i7 -to $tmp_i_i6

# Reset path in ResetSynchronizer
set_max_delay -datapath_only -from [get_clocks pclk_raw] -to $tmp_i_i10 4.00

######################################################
# Put the timestamp in the bitstream USERCODE

set_property BITSTREAM.CONFIG.USR_ACCESS TIMESTAMP [current_design]

######################################################
# Bitstream generation flags

set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
#set_property CONFIG_VOLTAGE 1.8 [current_design]
#set_property CFGBVS GND [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
