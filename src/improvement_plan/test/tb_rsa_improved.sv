`default_nettype none
`timescale 1ns/1ps

module tb_rsa_improved;
    parameter integer WIDTH = 42;
    parameter integer WORD_BITS = 7;
    localparam integer CHUNKS = WIDTH / 7;
    localparam integer PAGES = (WIDTH + 13) / 14;
    localparam integer WORDS = (WIDTH + 1 + WORD_BITS - 1) / WORD_BITS;
    localparam integer MUL_LIMIT = WIDTH * (5 * WORDS + 4) + 8;
    localparam integer RSA_LIMIT = (2 * WIDTH + 1) * (MUL_LIMIT + 10) + 32;
    reg clk = 0, rst_n = 0, ena = 1;
    reg [7:0] ui_in = 0, uio_in = 0;
    wire [7:0] uo_out, uio_out, uio_oe;
    reg mul_start = 0;
    reg [WIDTH-1:0] mul_a = 0, mul_b = 0, mul_n = 2;
    wire [WIDTH-1:0] mul_result;
    wire mul_done;
    integer transactions = 0, products = 0;
    integer fd, scanned, cycles;
    reg [WIDTH-1:0] n, e, m, expected, saved_result;

    always #5 clk = ~clk;
    tt_um_rsa_improved #(.WIDTH(WIDTH), .WORD_BITS(WORD_BITS)) dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in),
        .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );
    rsa_improved_modmul #(.WIDTH(WIDTH), .WORD_BITS(WORD_BITS)) unit_mul (
        .clk(clk), .rst_n(rst_n), .ena(ena), .start(mul_start),
        .a(mul_a), .b(mul_b), .modulus(mul_n),
        .result(mul_result), .done(mul_done)
    );

    task ticks(input integer count);
        repeat (count) @(negedge clk);
    endtask

    task reset_chip;
        begin
            ena = 1; rst_n = 0; ui_in = 0; uio_in = 0; mul_start = 0;
            ticks(4);
            if (uo_out !== 0 || uio_out !== 0 || uio_oe !== 8'h7f)
                $fatal(1, "Reset outputs or GPIO directions incorrect");
            rst_n = 1;
            ticks(4);
        end
    endtask

    task pulse_start;
        begin
            uio_in[7] = 1; ticks(4);
            uio_in[7] = 0; ticks(4);
        end
    endtask

    task load_chunk(input [6:0] chunk);
        begin
            ui_in = {1'b0, chunk}; ticks(4);
            ui_in[7] = 1; ticks(4);
            ui_in[7] = 0; ticks(4);
        end
    endtask

    task load_frame(input [WIDTH-1:0] tn, te, tm);
        integer field, index;
        reg [WIDTH-1:0] operand;
        begin
            for (field = 0; field < 3; field = field + 1) begin
                case (field)
                    0: operand = tn;
                    1: operand = te;
                    2: operand = tm;
                endcase
                for (index = 0; index < CHUNKS; index = index + 1) begin
                    load_chunk((operand >> (7 * index)) & 7'h7f);
                    if (uo_out !== 0 || uio_out !== 0)
                        $fatal(1, "Output must be zero during loading");
                    if (field == 0 && index == 0) begin
                        // START before a complete frame must be ignored.
                        pulse_start();
                        if (uio_out[6] !== 0) $fatal(1, "Premature START accepted");
                    end
                end
            end
            // A surplus LOAD before START must not replace any operand.
            load_chunk(7'h7f);
        end
    endtask

    task transaction(input [WIDTH-1:0] tn, te, tm, answer);
        integer cycle, page;
        reg [PAGES*14-1:0] actual;
        reg [13:0] held_word;
        begin
            load_frame(tn, te, tm);
            pulse_start();
            cycle = 0;
            while (uio_out[6] !== 1'b1 && cycle < RSA_LIMIT) begin
                ticks(1);
                cycle = cycle + 1;
                if (cycle == 8 && uio_out[6] !== 1'b1) begin
                    // LOAD and START pulses while computing must be ignored.
                    load_chunk(7'h55);
                    pulse_start();
                    ena = 0; ticks(7); ena = 1;
                end
                if (uio_oe !== 8'h7f) $fatal(1, "GPIO directions changed");
            end
            if (uio_out[6] !== 1'b1) $fatal(1, "RSA timeout");
            actual = 0;
            for (page = 0; page < PAGES; page = page + 1) begin
                actual = actual | ({{(PAGES*14-14){1'b0}}, uio_out[5:0], uo_out}
                    << (14 * page));
                if (page != PAGES-1) pulse_start();
            end
            if (actual !== {{(PAGES*14-WIDTH){1'b0}}, answer})
                $fatal(1, "N=%h e=%h m=%h expected=%h got=%h", tn, te, tm, answer, actual);
            held_word = {uio_out[5:0], uo_out};
            pulse_start(); // Last word is clamped; no wrapping or restart.
            ena = 0; ticks(5); ena = 1; ticks(5);
            if (uio_out[6] !== 1'b1 || {uio_out[5:0], uo_out} !== held_word)
                $fatal(1, "Completed result did not remain stable");
            $display("RSA_RESULT %0d %h", transactions, actual);
            transactions = transactions + 1;
        end
    endtask

    initial begin
        reset_chip();
        // A strobe wholly within ena=0 must not consume a frame chunk.
        ena = 0; load_chunk(7'h7f); ena = 1; ticks(4);
        pulse_start();
        if (uio_out[6] !== 0) $fatal(1, "START without a frame accepted");

        fd = $fopen("mul_vectors.txt", "r");
        if (!fd) $fatal(1, "Missing multiplier vectors");
        while (!$feof(fd)) begin
            scanned = $fscanf(fd, "%h %h %h %h\n", mul_n, mul_a, mul_b, expected);
            if (scanned != 4) $fatal(1, "Malformed multiplier vector");
            mul_start = 1; ticks(1); mul_start = 0;
            cycles = 0;
            while (mul_done !== 1'b1 && cycles < MUL_LIMIT) begin
                ticks(1); cycles = cycles + 1;
                if (cycles == 7) begin
                    saved_result = mul_result;
                    ena = 0; ticks(7);
                    if (mul_result !== saved_result || mul_done !== 0)
                        $fatal(1, "Multiplier did not pause with ena=0");
                    ena = 1;
                end
            end
            if (mul_done !== 1'b1 || mul_result !== expected)
                $fatal(1, "modmul N=%h a=%h b=%h expected=%h got=%h", mul_n, mul_a, mul_b, expected, mul_result);
            products = products + 1;
            ticks(2);
        end
        $fclose(fd);

        fd = $fopen("rsa_vectors.txt", "r");
        if (!fd) $fatal(1, "Missing exponentiation vectors");
        while (!$feof(fd)) begin
            scanned = $fscanf(fd, "%h %h %h %h\n", n, e, m, expected);
            if (scanned != 4) $fatal(1, "Malformed exponentiation vector");
            // All these transactions share one reset and stream their results.
            transaction(n, e, m, expected);
        end
        $fclose(fd);

        // Reset aborts both a partial frame and an active calculation.
        load_chunk(7'h12); load_chunk(7'h34);
        reset_chip();
        load_frame({WIDTH{1'b1}}, {WIDTH{1'b1}}, {{(WIDTH-1){1'b1}}, 1'b0});
        pulse_start(); ticks(20);
        reset_chip();
        transaction(3233, 17, 65, 2790);
        $display("PASS width=%0d word_bits=%0d rsa=%0d modmul=%0d", WIDTH, WORD_BITS, transactions, products);
        $finish;
    end
endmodule

`default_nettype wire
