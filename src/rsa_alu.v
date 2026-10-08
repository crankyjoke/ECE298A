`default_nettype none

module rsa_alu (
    input  wire [28:0] a,
    input  wire [28:0] b,
    input  wire        subtract,
    output wire [28:0] value
);

    assign value = a + (b ^ {29{subtract}}) + {28'b0, subtract};
endmodule

`default_nettype wire