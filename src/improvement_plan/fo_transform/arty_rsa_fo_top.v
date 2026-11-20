`default_nettype none

// Same port names as the existing arty_rsa_top/XDC. result_high now carries
// {HASH_REQUEST, REJECTED, data[11:8]}; it is not six extra ciphertext bits.
module arty_rsa_fo_top #(
    parameter integer WIDTH=28,
    parameter integer SEED_BITS=7, COIN_BITS=7, MESSAGE_BITS=7,
    parameter integer EXTERNAL_HASH=0, SMALL_HASH=1
) (
    input wire stm_clk,stm_rst_n,
    input wire [7:0] ui_in,
    input wire start,
    output wire [7:0] uo_out,
    output wire [5:0] result_high,
    output wire done,
    output wire [3:0] leds
);
    wire [7:0] uio_out,unused_oe;
    tt_um_rsa_fo #(.WIDTH(WIDTH),.SEED_BITS(SEED_BITS),.COIN_BITS(COIN_BITS),
        .MESSAGE_BITS(MESSAGE_BITS),.EXTERNAL_HASH(EXTERNAL_HASH),.SMALL_HASH(SMALL_HASH)) rsa (
        .clk(stm_clk),.rst_n(stm_rst_n),.ena(1'b1),
        .ui_in(ui_in),.uo_out(uo_out),.uio_in({start,7'b0}),
        .uio_out(uio_out),.uio_oe(unused_oe)
    );
    assign result_high=uio_out[5:0];
    assign done=uio_out[6];
    assign leds={~stm_rst_n,uio_out[4],uio_out[5],done};
endmodule
`default_nettype wire
