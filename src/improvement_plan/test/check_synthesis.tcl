# Optional synthesizability/resource check with an installed Vivado.
# This does NOT measure GF180 ASIC area or establish Tiny Tapeout tile fit.
# Run from a scratch directory inside improvement_plan/.build/:
# vivado -mode batch -source ../../test/check_synthesis.tcl -nojournal -nolog
set root [file dirname [file dirname [file normalize [info script]]]]
set output [file join $root .build fpga_synthesis]
file mkdir $output
set filenames {project.v rsa_loader.v rsa_modexp.v rsa_modmul.v rsa_alu.v}

set variants $argv
if {[llength $variants] == 0} {
    set variants {original28 improved28 improved42 improved56}
}
foreach variant $variants {
    create_project -in_memory -part xc7s25csga324-1
    if {$variant eq "original28"} {
        set directory [file dirname $root]
        set top tt_um_example
        foreach name $filenames {read_verilog [file join $directory $name]}
        synth_design -top $top -part xc7s25csga324-1 -mode out_of_context
    } else {
        set width [string range $variant 8 end]
        set top tt_um_rsa_improved
        foreach name $filenames {read_verilog [file join $root $name]}
        synth_design -top $top -part xc7s25csga324-1 -mode out_of_context \
            -generic [list WIDTH=$width WORD_BITS=7]
    }
    report_utilization -file [file join $output ${variant}_utilization.rpt]
    puts "SYNTHESIS_PASS $variant"
    close_project
}
