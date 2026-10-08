`default_nettype none
module rsa_modexp (
    input wire clk, rst_n, ena, start,
    input wire [27:0] modulus,
    input wire load,
    input wire [2:0] load_index,
    input wire [6:0] load_data,
    output reg [27:0] result,
    output wire done
);
    localparam [2:0] IDLE=0, CHECK=1, START_PRODUCT=2,
        WAIT_PRODUCT=3, CHECK_SQUARE=4, START_SQUARE=5,
        WAIT_SQUARE=6, FINISHED=7;
    reg [2:0] state;
    reg [27:0] base;
    reg [13:0] remaining;
    wire [27:0] mul_result;
    wire mul_done;
    wire mul_start = (state == START_PRODUCT) || (state == START_SQUARE);
    // Operand selection must persist throughout the multiplication.
    wire square = (state == START_SQUARE) || (state == WAIT_SQUARE);
    wire [27:0] mul_a = square ? base : result;
    rsa_modmul multiplier (
        .clk(clk), .rst_n(rst_n), .ena(ena), .start(mul_start),
        .a(mul_a), .b(base), .modulus(modulus),
        .result(mul_result), .done(mul_done)
    );
    assign done = (state == FINISHED);
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
                FINISHED: state <= FINISHED;
                default: state <= IDLE;
            endcase
        end
    end
    always @(posedge clk) begin
        if (rst_n && ena) begin
            if (load && state == IDLE) begin
                case (load_index)
                    4: remaining[6:0] <= load_data;
                    5: remaining[13:7] <= load_data;
                    6: base[6:0] <= load_data;
                    7: base[13:7] <= load_data;
                    default: begin end
                endcase
            end
            case (state)
                IDLE: if (start) begin
                    base[27:14] <= 0;
                    result <= 28'd1;
                end
                WAIT_PRODUCT: if (mul_done) result <= mul_result;
                CHECK_SQUARE: if (remaining == 1) remaining <= 0;
                WAIT_SQUARE: if (mul_done) begin
                    base <= mul_result;
                    remaining <= {1'b0, remaining[13:1]};
                end
                default: begin end
            endcase
        end
    end
endmodule
`default_nettype wire
