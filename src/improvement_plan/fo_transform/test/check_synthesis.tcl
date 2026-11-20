# Run in a scratch directory under improvement_plan/.build/.
# vivado -mode batch -source PATH_TO_THIS_SCRIPT -nojournal -nolog
# FPGA synthesis only: these reports do not establish GF180 tile fit.
set root [file dirname [file dirname [file normalize [info script]]]]
set parent [file dirname $root]
set output [file join $parent .build fo_synthesis_w28]
file mkdir $output
foreach external {1 0} {
    create_project -in_memory -part xc7s25csga324-1
    foreach name {rsa_alu.v rsa_modmul.v rsa_modexp.v} {
        read_verilog [file join $parent $name]
    }
    foreach name {sha256_block.v fo_hash.v rsa_adapter.v fo_engine.v project.v arty_rsa_fo_top.v} {
        read_verilog [file join $root $name]
    }
    synth_design -top arty_rsa_fo_top -part xc7s25csga324-1 -mode out_of_context \
        -generic [list WIDTH=28 SEED_BITS=7 COIN_BITS=7 MESSAGE_BITS=7 EXTERNAL_HASH=$external]
    report_utilization -file [file join $output hash_external_${external}.rpt]
    puts "FO_SYNTHESIS_PASS external=$external"
    close_project
}
