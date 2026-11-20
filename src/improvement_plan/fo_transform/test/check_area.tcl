# Compare arithmetic word widths at the same 28-bit RSA / seven-bit hash profile.
# FPGA resources are a screening metric; validate ASIC fit with the GF180 flow.
set root [file dirname [file dirname [file normalize [info script]]]]
set parent [file dirname $root]
set output [file join $parent .build fo_area_sweep]
file mkdir $output
foreach wordbits {1 2 4 7} {
    create_project -in_memory -part xc7s25csga324-1
    foreach name {rsa_alu.v rsa_modmul.v} {read_verilog [file join $parent $name]}
    foreach name {sha256_block.v tiny_hash7.v fo_hash.v rsa_adapter.v fo_engine.v project.v arty_rsa_fo_top.v} {
        read_verilog [file join $root $name]
    }
    synth_design -top arty_rsa_fo_top -part xc7s25csga324-1 -mode out_of_context \
        -generic [list WIDTH=28 WORD_BITS=$wordbits EXTERNAL_HASH=0 SMALL_HASH=1]
    report_utilization -file [file join $output wordbits_${wordbits}.rpt]
    puts "FO_AREA_PASS wordbits=$wordbits"
    close_project
}
