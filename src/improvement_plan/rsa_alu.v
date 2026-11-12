`default_nettype none

// Carry-in is initially 0 for addition and 1 for two's-complement subtraction.
// During subtraction carry-out=1 means no borrow from the current word.
module rsa_improved_alu #(
    parameter integer WORD_BITS = 7
) (
    input  wire [WORD_BITS-1:0] a, b,
    input  wire subtract, carry_in,
    output wire [WORD_BITS-1:0] value,
    output wire carry_out
);
    assign {carry_out, value} = {1'b0, a}
        + {1'b0, (b ^ {WORD_BITS{subtract}})}
        + {{WORD_BITS{1'b0}}, carry_in};
endmodule

`default_nettype wire
