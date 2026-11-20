`default_nettype none

// Parallel-input, left-to-right modular exponentiation for the FO encryptor.
// The caller holds N, exponent and operand stable until response consumption.
// Reuse those inputs instead of duplicating the exponent and base registers.
module rsa_fo_adapter #(
    parameter integer WIDTH=28, WORD_BITS=2
) (
    input wire clk, rst_n, ena,
    input wire request_valid,
    output wire request_ready,
    input wire [WIDTH-1:0] modulus, exponent, operand,
    output wire response_valid,
    input wire response_ready,
    output reg [WIDTH-1:0] response_value
);
    localparam integer INDEX_BITS=(WIDTH>1)?$clog2(WIDTH):1;
    localparam [2:0] IDLE=0, FIND_BIT=1, NEXT_BIT=2, SQUARE_START=3,
        SQUARE_WAIT=4, PRODUCT_START=5, PRODUCT_WAIT=6, RESPONSE=7;
    reg [2:0] state;
    reg [INDEX_BITS-1:0] bit_index;
    wire square=(state==SQUARE_START)||(state==SQUARE_WAIT);
    wire mul_start=(state==SQUARE_START)||(state==PRODUCT_START);
    wire mul_done;
    wire [WIDTH-1:0] mul_result;

    rsa_improved_modmul #(.WIDTH(WIDTH),.WORD_BITS(WORD_BITS)) multiplier (
        .clk(clk),.rst_n(rst_n),.ena(ena),.start(mul_start),
        .a(response_value),.b(square?response_value:operand),.modulus(modulus),
        .result(mul_result),.done(mul_done)
    );
    assign request_ready=(state==IDLE)&&ena;
    assign response_valid=(state==RESPONSE);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin state<=IDLE;bit_index<=0;end
        else if(ena) case(state)
            IDLE:if(request_valid) begin bit_index<=WIDTH-1;state<=FIND_BIT;end
            FIND_BIT:if(exponent[bit_index]) state<=NEXT_BIT;
                else if(bit_index==0) state<=RESPONSE;
                else bit_index<=bit_index-1'b1;
            NEXT_BIT:if(bit_index==0) state<=RESPONSE;
                else begin bit_index<=bit_index-1'b1;state<=SQUARE_START;end
            SQUARE_START:state<=SQUARE_WAIT;
            SQUARE_WAIT:if(mul_done) state<=exponent[bit_index]?PRODUCT_START:NEXT_BIT;
            PRODUCT_START:state<=PRODUCT_WAIT;
            PRODUCT_WAIT:if(mul_done) state<=NEXT_BIT;
            RESPONSE:if(response_ready) state<=IDLE;
            default:state<=IDLE;
        endcase
    end
    always @(posedge clk) begin
        if(rst_n&&ena) case(state)
            IDLE:if(request_valid) response_value<={{(WIDTH-1){1'b0}},1'b1};
            FIND_BIT:if(exponent[bit_index]) response_value<=operand;
            SQUARE_WAIT,PRODUCT_WAIT:if(mul_done) response_value<=mul_result;
            default:begin end
        endcase
    end
endmodule
`default_nettype wire
