`default_nettype none

// Encryption-only educational hybrid FO profile. No private key or decrypt path.
// Inputs must stay stable from start until done (the GPIO top owns their banks).
module rsa_fo_engine #(
    parameter integer WIDTH=28, WORD_BITS=2,
    parameter integer SEED_BITS=7, COIN_BITS=7, MESSAGE_BITS=7,
    parameter integer EXTERNAL_HASH=0, SMALL_HASH=1,
    parameter integer HASH_BITS=(MESSAGE_BITS>COIN_BITS)?MESSAGE_BITS:COIN_BITS
) (
    input wire clk, rst_n, ena, clear, start, invalid_input,
    input wire [WIDTH-1:0] modulus, public_exponent,
    input wire [SEED_BITS-1:0] random_seed,
    input wire [MESSAGE_BITS-1:0] message,
    output wire busy, done, error,
    output wire [WIDTH-1:0] ciphertext_out,
    output wire [MESSAGE_BITS-1:0] masked_out,
    output wire hash_request_valid, hash_request_kind,
    output wire [SEED_BITS-1:0] hash_request_seed,
    output wire [MESSAGE_BITS-1:0] hash_request_message,
    input wire hash_request_ready, hash_response_valid,
    input wire [HASH_BITS-1:0] hash_response_value,
    output wire hash_response_ready
);
    localparam [2:0] IDLE=0, G_REQ=1, G_WAIT=2, H_REQ=3, H_WAIT=4,
        ENC_REQ=5, ENC_WAIT=6, FINISHED=7;
    localparam integer ENCODED_BITS=SEED_BITS+COIN_BITS;
    localparam [WIDTH-1:0] MIN_MODULUS=({{(WIDTH-1){1'b0}},1'b1} << ENCODED_BITS);
    reg [2:0] state;
    reg valid_output;
    reg [COIN_BITS-1:0] coins;
    reg [MESSAGE_BITS-1:0] masked;
    wire local_rst_n=rst_n && !clear;
    wire hash_kind=(state==H_REQ)||(state==H_WAIT);
    wire hash_ready, hash_valid;
    wire [HASH_BITS-1:0] hash_value;
    wire rsa_ready, rsa_valid;
    wire [WIDTH-1:0] encoded={{(WIDTH-ENCODED_BITS){1'b0}},random_seed,coins};
    wire [WIDTH-1:0] rsa_result;

    rsa_fo_hash #(.SEED_BITS(SEED_BITS),.MESSAGE_BITS(MESSAGE_BITS),
        .VALUE_BITS(HASH_BITS),.EXTERNAL_HASH(EXTERNAL_HASH),.SMALL_HASH(SMALL_HASH)) hashes (
        .clk(clk),.rst_n(local_rst_n),.ena(ena),
        .request_valid((state==G_REQ)||(state==H_REQ)),.request_kind(hash_kind),
        .request_seed(random_seed),.request_message(hash_kind?message:{MESSAGE_BITS{1'b0}}),
        .request_ready(hash_ready),.response_valid(hash_valid),.response_value(hash_value),
        .response_ready(ena && ((state==G_WAIT)||(state==H_WAIT))),
        .external_request_valid(hash_request_valid),.external_request_kind(hash_request_kind),
        .external_request_seed(hash_request_seed),.external_request_message(hash_request_message),
        .external_request_ready(hash_request_ready),.external_response_valid(hash_response_valid),
        .external_response_value(hash_response_value),.external_response_ready(hash_response_ready)
    );
    rsa_fo_adapter #(.WIDTH(WIDTH),.WORD_BITS(WORD_BITS)) exponentiator (
        .clk(clk),.rst_n(local_rst_n),.ena(ena),.request_valid(state==ENC_REQ),
        .request_ready(rsa_ready),.modulus(modulus),.exponent(public_exponent),
        .operand(encoded),.response_valid(rsa_valid),.response_ready(ena && state==ENC_WAIT),
        .response_value(rsa_result)
    );
    assign busy=(state!=IDLE)&&(state!=FINISHED);
    assign done=(state==FINISHED);
    assign error=done && !valid_output;
    assign ciphertext_out=(done && valid_output)?rsa_result:{WIDTH{1'b0}};
    assign masked_out=(done && valid_output)?masked:{MESSAGE_BITS{1'b0}};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin state<=IDLE;valid_output<=0;end
        else if (clear) begin state<=IDLE;valid_output<=0;end
        else if (ena) case(state)
            IDLE,FINISHED: if (start) begin
                valid_output<=0;
                state<=(invalid_input || modulus<MIN_MODULUS || public_exponent==0)?FINISHED:G_REQ;
            end
            G_REQ: if (hash_ready) state<=G_WAIT;
            G_WAIT: if (hash_valid) state<=H_REQ;
            H_REQ: if (hash_ready) state<=H_WAIT;
            H_WAIT: if (hash_valid) state<=ENC_REQ;
            ENC_REQ: if (rsa_ready) state<=ENC_WAIT;
            ENC_WAIT: if (rsa_valid) begin valid_output<=1;state<=FINISHED;end
            default: begin state<=IDLE;valid_output<=0;end
        endcase
    end
    always @(posedge clk) begin
        if (rst_n && !clear && ena) case(state)
            G_WAIT: if (hash_valid) masked<=message ^ hash_value[MESSAGE_BITS-1:0];
            H_WAIT: if (hash_valid) coins<=hash_value[COIN_BITS-1:0];
            default:begin end
        endcase
    end
`ifndef SYNTHESIS
    initial begin
        if (WIDTH<14 || WIDTH%7!=0 || ENCODED_BITS>=WIDTH || HASH_BITS>256
            || SEED_BITS<1 || COIN_BITS<1 || MESSAGE_BITS<1 || HASH_BITS<COIN_BITS || HASH_BITS<MESSAGE_BITS)
            $fatal(1,"Invalid FO parameters: require SEED_BITS+COIN_BITS<WIDTH");
    end
`endif
endmodule
`default_nettype wire
