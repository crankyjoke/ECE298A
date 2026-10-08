`default_nettype none

module rsa_modexp (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ena,
    input  wire        start,
    input  wire [27:0] modulus,
    input  wire [13:0] exponent,
    input  wire [13:0] message,
    output reg  [27:0] result,
    output wire        done
);

    localparam [2:0]
        IDLE          = 0,
        CHECK         = 1,
        START_PRODUCT = 2,
        WAIT_PRODUCT  = 3,
        CHECK_SQUARE  = 4,
        START_SQUARE  = 5,
        WAIT_SQUARE   = 6,
        FINISHED      = 7;

    reg [2:0] state;
    reg [27:0] base;
    reg [13:0] remaining;

    wire [27:0] mul_result;
    wire mul_done;

    wire mul_start =
        (state == START_PRODUCT) || (state == START_SQUARE);

    wire [27:0] mul_a =
        (state == START_SQUARE) ? base : result;

    rsa_modmul multiplier (
        .clk(clk),
        .rst_n(rst_n),
        .ena(ena),
        .start(mul_start),
        .a(mul_a),
        .b(base),
        .modulus(modulus),
        .result(mul_result),
        .done(mul_done)
    );

    assign done = (state == FINISHED);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            base <= 0;
            remaining <= 0;
            result <= 0;
        end else if (ena) begin
            case (state)
                IDLE: if (start) begin
                    base <= {14'b0, message};
                    remaining <= exponent;
                    result <= 28'd1;
                    state <= CHECK;
                end

                CHECK: begin
                    if (remaining == 0)
                        state <= FINISHED;
                    else if (remaining[0])
                        state <= START_PRODUCT;
                    else
                        state <= CHECK_SQUARE;
                end

                START_PRODUCT: state <= WAIT_PRODUCT;

                WAIT_PRODUCT: if (mul_done) begin
                    result <= mul_result;
                    state <= CHECK_SQUARE;
                end

                CHECK_SQUARE: begin
                    if (remaining == 1) begin
                        remaining <= 0;
                        state <= CHECK;
                    end else begin
                        state <= START_SQUARE;
                    end
                end

                START_SQUARE: state <= WAIT_SQUARE;

                WAIT_SQUARE: if (mul_done) begin
                    base <= mul_result;
                    remaining <= {1'b0, remaining[13:1]};
                    state <= CHECK;
                end

                FINISHED: state <= FINISHED;

                default: state <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire