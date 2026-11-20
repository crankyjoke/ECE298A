`default_nettype none

// Educational classical hybrid FO profile. See README for exact encoding,
// truncation and security limits; this is not standardized RSA padding.
module rsa_fo_engine #(
    parameter integer WIDTH=28, WORD_BITS=7,
    parameter integer SEED_BITS=7, COIN_BITS=7, MESSAGE_BITS=7,
    parameter integer EXTERNAL_HASH=0,
    parameter integer HASH_BITS=(MESSAGE_BITS>COIN_BITS)?MESSAGE_BITS:COIN_BITS
) (
    input wire clk, rst_n, ena, clear, start, decrypt,
    input wire [WIDTH-1:0] modulus, public_exponent, private_exponent, ciphertext_in,
    input wire [SEED_BITS-1:0] random_seed,
    input wire [MESSAGE_BITS-1:0] payload,
    output wire busy, done, rejected,
    output reg accepted,
    output wire [WIDTH-1:0] ciphertext_out,
    output wire [MESSAGE_BITS-1:0] masked_out, plaintext_out,
    output wire hash_request_valid, hash_request_kind,
    output wire [SEED_BITS-1:0] hash_request_seed,
    output wire [MESSAGE_BITS-1:0] hash_request_message,
    input wire hash_request_ready, hash_response_valid,
    input wire [HASH_BITS-1:0] hash_response_value,
    output wire hash_response_ready
);
    localparam [3:0] IDLE=0, G_REQ=1, G_WAIT=2, H_REQ=3, H_WAIT=4,
        DEC_REQ=5, DEC_WAIT=6, ENC_REQ=7, ENC_WAIT=8, FINISHED=9;
    localparam integer ENCODED_BITS=SEED_BITS+COIN_BITS;
    localparam [WIDTH-1:0] MIN_MODULUS=({{(WIDTH-1){1'b0}},1'b1} << ENCODED_BITS);
    reg [3:0] state;
    reg decrypting, bad;
    reg [SEED_BITS-1:0] sigma;
    reg [COIN_BITS-1:0] coins;
    reg [MESSAGE_BITS-1:0] candidate, masked;
    wire local_rst_n=rst_n && !clear;
    wire hash_req=(state==G_REQ)||(state==H_REQ);
    wire hash_kind=(state==H_REQ)||(state==H_WAIT);
    wire hash_ready, hash_valid;
    wire [HASH_BITS-1:0] hash_value;
    wire hash_take=ena && ((state==G_WAIT)||(state==H_WAIT));
    wire rsa_req=(state==DEC_REQ)||(state==ENC_REQ);
    wire rsa_ready, rsa_valid;
    wire decoding=(state==DEC_REQ)||(state==DEC_WAIT);
    wire [WIDTH-1:0] encoded={{(WIDTH-ENCODED_BITS){1'b0}},sigma,coins};
    wire [WIDTH-1:0] rsa_input=decoding ? ((ciphertext_in<modulus)?ciphertext_in:{WIDTH{1'b0}}) : encoded;
    wire [WIDTH-1:0] rsa_result;
    wire rsa_take=ena && ((state==DEC_WAIT)||(state==ENC_WAIT));

    rsa_fo_hash #(.SEED_BITS(SEED_BITS),.MESSAGE_BITS(MESSAGE_BITS),
        .VALUE_BITS(HASH_BITS),.EXTERNAL_HASH(EXTERNAL_HASH)) hashes (
        .clk(clk),.rst_n(local_rst_n),.ena(ena),
        .request_valid(hash_req),.request_kind(hash_kind),
        .request_seed(sigma),.request_message(hash_kind?candidate:{MESSAGE_BITS{1'b0}}),.request_ready(hash_ready),
        .response_valid(hash_valid),.response_value(hash_value),.response_ready(hash_take),
        .external_request_valid(hash_request_valid),.external_request_kind(hash_request_kind),
        .external_request_seed(hash_request_seed),.external_request_message(hash_request_message),
        .external_request_ready(hash_request_ready),.external_response_valid(hash_response_valid),
        .external_response_value(hash_response_value),.external_response_ready(hash_response_ready)
    );
    rsa_fo_adapter #(.WIDTH(WIDTH),.WORD_BITS(WORD_BITS)) exponentiator (
        .clk(clk),.rst_n(local_rst_n),.ena(ena),.request_valid(rsa_req),.request_ready(rsa_ready),
        .modulus(modulus),.exponent(decoding?private_exponent:public_exponent),
        .operand(rsa_input),.response_valid(rsa_valid),.response_ready(rsa_take),
        .response_value(rsa_result)
    );
    assign busy=(state!=IDLE)&&(state!=FINISHED);
    assign done=(state==FINISHED);
    assign rejected=done && !accepted;
    // The reused RSA result register already holds the final ciphertext.
    assign ciphertext_out=(done && accepted && !decrypting)?rsa_result:{WIDTH{1'b0}};
    assign masked_out=(done && accepted && !decrypting)?masked:{MESSAGE_BITS{1'b0}};
    // Never release the candidate plaintext before verification succeeds.
    assign plaintext_out=(done && accepted && decrypting)?candidate:{MESSAGE_BITS{1'b0}};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin state<=IDLE; accepted<=0; bad<=0; decrypting<=0; end
        else if (clear) begin state<=IDLE; accepted<=0; bad<=0; decrypting<=0; end
        else if (ena) case(state)
            IDLE,FINISHED: if (start) begin
                accepted<=0;
                decrypting<=decrypt;
                bad<=0;
                if (modulus<MIN_MODULUS || public_exponent==0 || (decrypt && private_exponent==0))
                    state<=FINISHED;
                else if (decrypt) begin bad<=(ciphertext_in>=modulus); state<=DEC_REQ; end
                else state<=G_REQ;
            end
            G_REQ: if (hash_ready) state<=G_WAIT;
            G_WAIT: if (hash_valid) state<=H_REQ;
            H_REQ: if (hash_ready) state<=H_WAIT;
            H_WAIT: if (hash_valid) state<=ENC_REQ;
            DEC_REQ: if (rsa_ready) state<=DEC_WAIT;
            DEC_WAIT: if (rsa_valid) begin
                bad<=bad || (|rsa_result[WIDTH-1:ENCODED_BITS]);
                state<=G_REQ;
            end
            ENC_REQ: if (rsa_ready) state<=ENC_WAIT;
            ENC_WAIT: if (rsa_valid) begin
                accepted<=!decrypting || (!bad && rsa_result==ciphertext_in);
                state<=FINISHED;
            end
            default: begin state<=IDLE; accepted<=0; end
        endcase
    end
    // These registers are initialized before use and hidden until completion.
    always @(posedge clk) begin
        if (rst_n && !clear && ena) case(state)
            IDLE,FINISHED: if (start && !decrypt && modulus>=MIN_MODULUS && public_exponent!=0) begin
                sigma<=random_seed; candidate<=payload;
            end
            G_WAIT: if (hash_valid) begin
                if (decrypting) begin candidate<=payload ^ hash_value[MESSAGE_BITS-1:0]; masked<=payload; end
                else masked<=candidate ^ hash_value[MESSAGE_BITS-1:0];
            end
            H_WAIT: if (hash_valid) coins<=hash_value[COIN_BITS-1:0];
            DEC_WAIT: if (rsa_valid) sigma<=rsa_result[COIN_BITS +: SEED_BITS];
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
