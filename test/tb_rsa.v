`timescale 1ns / 1ps
`default_nettype none

// Standalone RTL regression. Drive and check only the public Tiny Tapeout pins.
// Select tb_rsa as the simulation top; tb.v is the separate cocotb harness.
module tb_rsa;
    localparam integer MAX_CYCLES = 6000;
    localparam integer RANDOM_CASES = 200;

    reg clk = 1'b0;
    reg rst_n = 1'b1;
    reg ena = 1'b1;
    reg [7:0] ui_in = 8'b0;
    reg [7:0] uio_in = 8'b0;
    wire [7:0] uo_out, uio_out, uio_oe;
    integer cases_passed = 0;
    integer baseline_cycles, paused_cycles, unused_cycles;
    integer index;
    reg [31:0] random_state = 32'd298;
    reg [27:0] random_modulus;
    reg [13:0] random_exponent, random_message;

    tt_um_example dut (
        .ui_in(ui_in), .uo_out(uo_out),
        .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );

    always #5 clk = ~clk;

    // Sample after the active clock edge and drive with time before the next one.
    task ticks;
        input integer count;
        integer cycle;
        begin
            for (cycle = 0; cycle < count; cycle = cycle + 1) begin
                @(negedge clk);
                #1;
            end
        end
    endtask

    // Independent MSB-first reference using wide arithmetic and remainder.
    // The DUT uses LSB-first exponentiation and iterative add/subtract reduction.
    function [27:0] reference_pow;
        input [27:0] modulus;
        input [13:0] exponent, message;
        reg [63:0] value;
        integer bit_number;
        begin
            value = 64'd1;
            for (bit_number = 13; bit_number >= 0; bit_number = bit_number - 1) begin
                value = (value * value) % {36'b0, modulus};
                if (exponent[bit_number])
                    value = (value * {50'b0, message}) % {36'b0, modulus};
            end
            reference_pow = value[27:0];
        end
    endfunction

    // Explicit PRNG makes the random vectors identical across simulators.
    function [31:0] next_random;
        input [31:0] previous;
        begin
            next_random = previous * 32'd1664525 + 32'd1013904223;
        end
    endfunction

    task check_idle_outputs;
        begin
            if (uo_out !== 8'b0 || uio_out !== 8'b0)
                $fatal(1, "Outputs must be zero before DONE: uo=%h uio=%h at %t",
                       uo_out, uio_out, $time);
            if (uio_oe !== 8'h7f)
                $fatal(1, "Incorrect pin directions: uio_oe=%h", uio_oe);
        end
    endtask

    task reset_dut;
        begin
            // Calls after startup occur between rising edges. Check that reset
            // clears DONE without waiting for another rising clock edge.
            rst_n = 1'b0;
            ena = 1'b1;
            ui_in = 8'b0;
            uio_in = 8'b0;
            #1;
            check_idle_outputs;
            ticks(4);
            rst_n = 1'b1;
            ticks(4);
            check_idle_outputs;
        end
    endtask

    task load_chunk;
        input [6:0] chunk;
        input integer high_cycles;
        begin
            // Bundled data settles before LOAD and stays stable throughout it.
            ui_in = {1'b0, chunk};
            ticks(4);
            ui_in = {1'b1, chunk};
            ticks(high_cycles);
            ui_in = {1'b0, chunk};
            ticks(4);
        end
    endtask

    task load_operands;
        input [27:0] modulus;
        input [13:0] exponent, message;
        reg [55:0] packet;
        integer chunk_number;
        begin
            packet = {message, exponent, modulus};
            for (chunk_number = 0; chunk_number < 8; chunk_number = chunk_number + 1) begin
                load_chunk(packet[6:0], 4 + 3 * (chunk_number % 3));
                packet = packet >> 7;
            end
        end
    endtask

    task pulse_start;
        input integer high_cycles;
        begin
            uio_in[7] = 1'b1;
            ticks(high_cycles);
            uio_in[7] = 1'b0;
        end
    endtask

    task check_result;
        input [27:0] expected;
        reg [13:0] low_page, high_page;
        reg [27:0] actual;
        begin
            // Other data bits must not affect page selection after loading.
            ui_in = 8'h7e;
            ticks(4);
            if (uio_out[6] !== 1'b1)
                $fatal(1, "DONE dropped while selecting the low page");
            low_page = {uio_out[5:0], uo_out};
            ui_in = 8'h01;
            ticks(4);
            if (uio_out[6] !== 1'b1)
                $fatal(1, "DONE dropped while selecting the high page");
            high_page = {uio_out[5:0], uo_out};
            actual = {high_page, low_page};
            if (actual !== expected)
                $fatal(1, "Case %0d: expected ciphertext %0d (0x%h), got %0d (0x%h)",
                       cases_passed + 1, expected, expected, actual, actual);

            // Switch back to catch a selector that only works in one direction.
            ui_in = 8'h00;
            ticks(4);
            if ({uio_out[5:0], uo_out} !== expected[13:0])
                $fatal(1, "Low result page changed after switching back");
        end
    endtask

    task finish_transaction;
        input [27:0] modulus;
        input [13:0] exponent, message;
        input integer pause_length;
        output integer active_cycles;
        reg [27:0] expected;
        begin
            expected = reference_pow(modulus, exponent, message);
            pulse_start(4);
            active_cycles = 0;
            while (uio_out[6] !== 1'b1 && active_cycles < MAX_CYCLES) begin
                if (pause_length != 0 && active_cycles == 20) begin
                    ena = 1'b0;
                    ticks(pause_length);
                    check_idle_outputs;
                    ena = 1'b1;
                end
                ticks(1);
                active_cycles = active_cycles + 1;
            end
            if (uio_out[6] !== 1'b1)
                $fatal(1, "Timeout: N=%0d e=%0d m=%0d after %0d active cycles",
                       modulus, exponent, message, active_cycles);
            check_result(expected);
            ticks(8);
            if (uio_out[6] !== 1'b1 || {uio_out[5:0], uo_out} !== expected[13:0])
                $fatal(1, "DONE/result did not remain stable until reset");
            cases_passed = cases_passed + 1;
            if (cases_passed <= 18 || cases_passed % 50 == 0)
                $display("PASS case %0d: N=%0d e=%0d m=%0d c=%0d (%0d active wait cycles)",
                         cases_passed, modulus, exponent, message, expected, active_cycles);
        end
    endtask

    task run_case;
        input [27:0] modulus;
        input [13:0] exponent, message;
        input integer pause_length;
        output integer active_cycles;
        begin
            if (modulus < 2 || {14'b0, message} >= modulus)
                $fatal(1, "Test vector is outside the implemented input contract");
            reset_dut;
            load_operands(modulus, exponent, message);
            check_idle_outputs;
            finish_transaction(modulus, exponent, message, pause_length, active_cycles);
        end
    endtask

    task test_protocol;
        reg [55:0] packet;
        integer chunk_number;
        begin
            $display("Checking LOAD/START protocol and fixed pin directions");
            reset_dut;

            // A LOAD edge while disabled must not consume a chunk or be replayed.
            ena = 1'b0;
            load_chunk(7'h7f, 12);
            ena = 1'b1;
            ticks(8);
            check_idle_outputs;

            // START must be ignored before the eighth chunk has been captured.
            pulse_start(8);
            ticks(8);
            check_idle_outputs;
            packet = {14'd65, 14'd17, 28'd3233};
            for (chunk_number = 0; chunk_number < 8; chunk_number = chunk_number + 1) begin
                // Holding LOAD high must still capture exactly one chunk.
                load_chunk(packet[6:0], 12);
                packet = packet >> 7;
                if (chunk_number != 7) begin
                    pulse_start(8);
                    ticks(8);
                    check_idle_outputs;
                end
            end

            // START while disabled must be ignored, even after loading completes.
            ena = 1'b0;
            pulse_start(8);
            ticks(8);
            ena = 1'b1;
            ticks(8);
            check_idle_outputs;

            // Further LOAD edges after eight chunks must not overwrite operands.
            load_chunk(7'h7f, 12);
            finish_transaction(28'd3233, 14'd17, 14'd65, 0, unused_cycles);
            if (reference_pow(28'd3233, 14'd17, 14'd65) !== 28'd2790)
                $fatal(1, "Reference model failed the known RSA example");

            // DONE/result remain latched through extra strobes and deselection.
            load_chunk(7'h55, 12);
            pulse_start(12);
            ticks(8);
            check_result(28'd2790);
            ena = 1'b0;
            ticks(8);
            check_result(28'd2790);
            ena = 1'b1;
        end
    endtask

    // Check the visible interface throughout loading and computation as well as
    // at transaction boundaries. No assumptions about unreset internal data.
    always @(negedge clk) begin
        #2;
        if (uio_oe !== 8'h7f)
            $fatal(1, "uio_oe must always be 0x7f, got %h at %t", uio_oe, $time);
        if (uio_out[7] !== 1'b0)
            $fatal(1, "Output value for input-only pin 7 must be zero");
        if (uio_out[6] !== 1'b0 && uio_out[6] !== 1'b1)
            $fatal(1, "DONE is unknown at %t", $time);
        if (uio_out[6] === 1'b0 &&
            (uo_out !== 8'b0 || uio_out[5:0] !== 6'b0))
            $fatal(1, "Result pins must be masked until DONE at %t", $time);
    end

    initial begin
        if ($test$plusargs("WAVES")) begin
            $dumpfile("rsa.vcd");
            $dumpvars(0, tb_rsa);
        end

        test_protocol;

        // Compare elapsed enabled cycles as well as the answer to prove pausing
        // freezes progress, rather than merely hiding an incorrect intermediate.
        $display("Checking enable pause/resume and directed arithmetic cases");
        run_case(28'd3233, 14'd17, 14'd65, 0, baseline_cycles);
        run_case(28'd3233, 14'd17, 14'd65, 11, paused_cycles);
        if (paused_cycles != baseline_cycles)
            $fatal(1, "Enable pause changed active latency: baseline=%0d paused=%0d",
                   baseline_cycles, paused_cycles);

        run_case(28'd2, 14'd0, 14'd0, 0, unused_cycles);
        run_case(28'd2, 14'd1, 14'd1, 0, unused_cycles);
        run_case(28'd2, 14'd16383, 14'd0, 0, unused_cycles);
        run_case(28'd3, 14'd16383, 14'd2, 0, unused_cycles);
        run_case(28'hfffffff, 14'd16383, 14'd16383, 0, unused_cycles);
        run_case(28'hfffffff, 14'd8192, 14'd16382, 0, unused_cycles);
        run_case(28'hfffffff, 14'd2, 14'd16383, 0, unused_cycles);
        run_case(28'hfffffff, 14'd0, 14'd0, 0, unused_cycles);
        run_case(28'h8000001, 14'd16383, 14'd16383, 0, unused_cycles);
        run_case(28'd16381, 14'd0, 14'd123, 0, unused_cycles);
        run_case(28'd16384, 14'd1, 14'd16383, 0, unused_cycles);
        run_case(28'd100, 14'd12345, 14'd0, 0, unused_cycles);
        run_case(28'd100, 14'd8192, 14'd99, 0, unused_cycles);

        $display("Checking reset during partial loading and active computation");
        reset_dut;
        load_chunk(7'h7f, 4);
        load_chunk(7'h7f, 4);
        run_case(28'd3233, 14'd17, 14'd65, 0, unused_cycles);
        reset_dut;
        load_operands(28'hfffffff, 14'd16383, 14'd16383);
        pulse_start(4);
        ticks(32);
        check_idle_outputs;
        ena = 1'b0;
        // Assert reset while disabled, then enable only after it has taken effect.
        rst_n = 1'b0;
        #1;
        check_idle_outputs;
        ticks(4);
        run_case(28'd100, 14'd8192, 14'd99, 0, unused_cycles);

        $display("Checking %0d reproducible random transactions (seed 298)", RANDOM_CASES);
        for (index = 0; index < RANDOM_CASES; index = index + 1) begin
            random_state = next_random(random_state);
            if (index % 2 == 0)
                random_modulus = 28'd2 + (random_state % 32'd16383);
            else
                random_modulus = 28'd2 + (random_state % 32'd268435454);
            random_state = next_random(random_state);
            random_exponent = random_state[13:0];
            random_state = next_random(random_state);
            if (random_modulus < 28'd16384)
                random_message = random_state % {4'b0, random_modulus};
            else
                random_message = random_state[13:0];
            run_case(random_modulus, random_exponent, random_message, 0, unused_cycles);
        end

        $display("PASS: all RSA tests passed (%0d transactions)", cases_passed);
        $finish;
    end

    initial begin
        #20000000;
        $fatal(1, "Global simulation watchdog expired");
    end
endmodule

`default_nettype wire
