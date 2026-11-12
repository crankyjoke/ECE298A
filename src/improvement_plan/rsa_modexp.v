`default_nettype none

module rsa_improved_modexp #(
    parameter integer WIDTH = 42,
    parameter integer WORD_BITS = 7
) (
    input  wire clk, rst_n, ena, start,
    input  wire [WIDTH-1:0] modulus,
    input  wire load,
    input  wire [1:0] load_field,
    input  wire [6:0] load_data,
    output reg  [WIDTH-1:0] result,
    output wire busy, done
);
    localparam [2:0] IDLE=0, CHECK=1, START_PRODUCT=2, WAIT_PRODUCT=3,
        CHECK_SQUARE=4, START_SQUARE=5, WAIT_SQUARE=6, FINISHED=7;
    reg [2:0] state;
    reg [WIDTH-1:0] base, remaining;
    wire [WIDTH-1:0] mul_result;
    wire mul_done;
    wire mul_start = (state == START_PRODUCT) || (state == START_SQUARE);
    wire square = (state == START_SQUARE) || (state == WAIT_SQUARE);
    wire [WIDTH-1:0] mul_a = square ? base : result;

    rsa_improved_modmul #(.WIDTH(WIDTH), .WORD_BITS(WORD_BITS)) multiplier (
        .clk(clk), .rst_n(rst_n), .ena(ena), .start(mul_start),
        .a(mul_a), .b(base), .modulus(modulus),
        .result(mul_result), .done(mul_done)
    );
    assign done = (state == FINISHED);
    assign busy = (state != IDLE) && (state != FINISHED);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else if (ena) begin
            case (state)
                IDLE: if (start) state <= CHECK;
                CHECK: begin
                    if (remaining == 0) state <= FINISHED;
                    else if (remaining[0]) state <= START_PRODUCT;
                    else state <= CHECK_SQUARE;
                end
                START_PRODUCT: state <= WAIT_PRODUCT;
                WAIT_PRODUCT: if (mul_done) state <= CHECK_SQUARE;
                CHECK_SQUARE: state <= (remaining == 1) ? CHECK : START_SQUARE;
                START_SQUARE: state <= WAIT_SQUARE;
                WAIT_SQUARE: if (mul_done) state <= CHECK;
                // The first next-frame LOAD clears DONE and re-arms the core.
                FINISHED: if (load) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst_n && ena) begin
            if (load && !busy) begin
                case (load_field)
                    1: remaining <= {load_data, remaining[WIDTH-1:7]};
                    2: base <= {load_data, base[WIDTH-1:7]};
                    default: begin end
                endcase
            end
            case (state)
                IDLE: if (start) result <= {{(WIDTH-1){1'b0}}, 1'b1};
                WAIT_PRODUCT: if (mul_done) result <= mul_result;
                CHECK_SQUARE: if (remaining == 1) remaining <= 0;
                WAIT_SQUARE: if (mul_done) begin
                    base <= mul_result;
                    remaining <= remaining >> 1;
                end
                default: begin end
            endcase
        end
    end
endmodule

`default_nettype wire
