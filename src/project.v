/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    reg [7:0] counter;
    // ui_in[0] controls load
    // ui_in[1] controls high Z
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            counter <= 8'b0;
        else if (ui_in[0])
            counter <= uio_in;
        else
            counter <= counter + 8'd1;
    end

    assign uo_out  = 8'b0;
    assign uio_out = counter;
    assign uio_oe  = {8{ui_in[1]}};
endmodule

  `default_nettype wire
