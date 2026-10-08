`default_nettype none
module tt_um_example (
    input wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input wire ena, clk, rst_n
);
    wire [27:0] modulus, result;
    wire [6:0] load_data;
    wire [2:0] load_index;
    wire load, start, done, page_select;
    wire [13:0] page = page_select ? result[27:14] : result[13:0];
    rsa_loader loader (
        .clk(clk), .rst_n(rst_n), .ena(ena), .ui_in(ui_in),
        .start_in(uio_in[7]), .modulus(modulus),
        .load_data(load_data), .load_index(load_index), .load(load),
        .start(start), .page_select(page_select)
    );
    rsa_modexp exponentiation (
        .clk(clk), .rst_n(rst_n), .ena(ena), .start(start),
        .modulus(modulus), .load(load), .load_index(load_index),
        .load_data(load_data), .result(result), .done(done)
    );
    assign uo_out = done ? page[7:0] : 8'b0;
    assign uio_out[5:0] = done ? page[13:8] : 6'b0;
    assign uio_out[6] = done;
    assign uio_out[7] = 1'b0;
    assign uio_oe = 8'b01111111;
endmodule
`default_nettype wire
