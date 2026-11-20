`default_nettype none

// Hash service shared by G and H. All request/response transfers require ena.
// External mode delegates only hashing, not the FO acceptance decision.
module rsa_fo_hash #(
    parameter integer SEED_BITS=7, MESSAGE_BITS=7, VALUE_BITS=7,
    parameter integer EXTERNAL_HASH=0
) (
    input wire clk, rst_n, ena,
    input wire request_valid, request_kind,
    input wire [SEED_BITS-1:0] request_seed,
    input wire [MESSAGE_BITS-1:0] request_message,
    output wire request_ready, response_valid,
    output wire [VALUE_BITS-1:0] response_value,
    input wire response_ready,
    output wire external_request_valid, external_request_kind,
    output wire [SEED_BITS-1:0] external_request_seed,
    output wire [MESSAGE_BITS-1:0] external_request_message,
    input wire external_request_ready, external_response_valid,
    input wire [VALUE_BITS-1:0] external_response_value,
    output wire external_response_ready
);
    localparam integer SEED_BYTES=(SEED_BITS+7)/8, MESSAGE_BYTES=(MESSAGE_BITS+7)/8;
    generate if (EXTERNAL_HASH != 0) begin: external_service
        assign external_request_valid = request_valid && ena;
        assign external_request_kind = request_kind;
        assign external_request_seed = request_seed;
        assign external_request_message = request_message;
        assign request_ready = external_request_ready && ena;
        assign response_valid = external_response_valid;
        assign response_value = external_response_value;
        assign external_response_ready = response_ready && ena;
    end else begin: hardware_service
        localparam [1:0] IDLE=0, RUNNING=1, RESPONSE=2;
        reg [1:0] state;
        reg [VALUE_BITS-1:0] value;
        wire [SEED_BYTES*8-1:0] seed_bytes = request_seed;
        wire [MESSAGE_BYTES*8-1:0] message_bytes = request_message;
        reg [511:0] block_g, block_h;
        integer i;
        wire [255:0] digest;
        wire sha_done, unused_busy;
        always @* begin
            block_g=0; block_h=0;
            block_g[511:480]=32'h464f4731; // ASCII FOG1
            block_h[511:480]=32'h464f4831; // ASCII FOH1
            for(i=0;i<SEED_BYTES;i=i+1) begin
                block_g[511-(4+i)*8 -: 8] = seed_bytes[(SEED_BYTES-1-i)*8 +: 8];
                block_h[511-(4+i)*8 -: 8] = seed_bytes[(SEED_BYTES-1-i)*8 +: 8];
            end
            for(i=0;i<MESSAGE_BYTES;i=i+1)
                block_h[511-(4+SEED_BYTES+i)*8 -: 8] = message_bytes[(MESSAGE_BYTES-1-i)*8 +: 8];
            block_g[511-(4+SEED_BYTES)*8 -: 8] = 8'h80;
            block_h[511-(4+SEED_BYTES+MESSAGE_BYTES)*8 -: 8] = 8'h80;
            block_g[63:0] = (4+SEED_BYTES)*8;
            block_h[63:0] = (4+SEED_BYTES+MESSAGE_BYTES)*8;
        end
        rsa_fo_sha256_block sha (
            .clk(clk),.rst_n(rst_n),.ena(ena),
            .start(request_valid && request_ready),
            .block(request_kind ? block_h : block_g),
            .busy(unused_busy),.done(sha_done),.digest(digest)
        );
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) state<=IDLE;
            else if (ena) case(state)
                IDLE: if (request_valid) state<=RUNNING;
                RUNNING: if (sha_done) state<=RESPONSE;
                RESPONSE: if (response_ready) state<=IDLE;
                default: state<=IDLE;
            endcase
        end
        always @(posedge clk) begin
            if (rst_n && ena && state==RUNNING && sha_done)
                value<=digest[VALUE_BITS-1:0];
        end
        assign request_ready = (state==IDLE) && ena;
        assign response_valid = (state==RESPONSE);
        assign response_value = value;
        assign external_request_valid=0;
        assign external_request_kind=0;
        assign external_request_seed=0;
        assign external_request_message=0;
        assign external_response_ready=0;
    end endgenerate
`ifndef SYNTHESIS
    initial begin
        if (SEED_BITS<1 || MESSAGE_BITS<1 || VALUE_BITS<1 || VALUE_BITS>256
            || 4+SEED_BYTES+MESSAGE_BYTES>55)
            $fatal(1,"FO hash inputs must fit one SHA-256 padded block");
    end
`endif
endmodule
`default_nettype wire
