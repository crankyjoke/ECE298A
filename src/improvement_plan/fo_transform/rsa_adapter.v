`default_nettype none

// Converts a parallel FO request into the existing seven-bit exponent loader.
// Request operands and modulus must stay stable until response consumption.
module rsa_fo_adapter #(
    parameter integer WIDTH=28, WORD_BITS=7
) (
    input wire clk, rst_n, ena,
    input wire request_valid,
    output wire request_ready,
    input wire [WIDTH-1:0] modulus, exponent, operand,
    output wire response_valid,
    input wire response_ready,
    output wire [WIDTH-1:0] response_value
);
    localparam integer CHUNKS=WIDTH/7, INDEX_BITS=(CHUNKS>1)?$clog2(CHUNKS):1;
    localparam [2:0] IDLE=0, RESET=1, LOAD_E=2, LOAD_M=3, START=4, WAITING=5, RESPONSE=6;
    reg [2:0] state;
    reg [INDEX_BITS-1:0] chunk_index;
    reg [6:0] chunk;
    integer i;
    wire [WIDTH-1:0] input_value=(state==LOAD_E)?exponent:operand;
    wire unused_busy, engine_done;
    wire engine_rst_n=rst_n && (state!=RESET);
    always @* begin
        chunk=0;
        for(i=0;i<CHUNKS;i=i+1)
            chunk=chunk | (input_value[i*7 +: 7] & {7{chunk_index==i}});
    end
    rsa_improved_modexp #(.WIDTH(WIDTH),.WORD_BITS(WORD_BITS)) core (
        .clk(clk),.rst_n(engine_rst_n),.ena(ena),.start(state==START),
        .modulus(modulus),.load((state==LOAD_E)||(state==LOAD_M)),
        .load_field((state==LOAD_E)?2'd1:2'd2),.load_data(chunk),
        .result(response_value),.busy(unused_busy),.done(engine_done)
    );
    assign request_ready=(state==IDLE) && ena;
    assign response_valid=(state==RESPONSE);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin state<=IDLE; chunk_index<=0; end
        else if (ena) case(state)
            IDLE: if (request_valid) state<=RESET;
            RESET: begin chunk_index<=0; state<=LOAD_E; end
            LOAD_E,LOAD_M: begin
                if (chunk_index==CHUNKS-1) begin
                    chunk_index<=0;
                    state<=(state==LOAD_E)?LOAD_M:START;
                end else chunk_index<=chunk_index+1'b1;
            end
            START: state<=WAITING;
            WAITING: if (engine_done) state<=RESPONSE;
            RESPONSE: if (response_ready) state<=IDLE;
            default: state<=IDLE;
        endcase
    end
endmodule
`default_nettype wire
