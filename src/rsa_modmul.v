`default_nettype none

module rsa_modmul (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ena,
    input  wire        start,
    input  wire [27:0] a,
    input  wire [27:0] b,
    input  wire [27:0] modulus,
    output wire [27:0] result,
    output wire        done
);
    // Requires 1 < modulus and a,b < modulus.
    // Keep modulus stable until the operation finishes.
    localparam [3:0]
        IDLE          = 0,
        CHECK         = 1,
        ADD           = 2,
        REDUCE_ADD    = 3,
        DOUBLE        = 4,
        REDUCE_DOUBLE = 5,
        SHIFT         = 6,
        FINISH        = 7;

    reg [3:0] state;
    reg [27:0] x, y, accumulator;
    reg [28:0] sum;

    reg [28:0] alu_a, alu_b;
    reg subtract;
    wire [28:0] alu_value;

    rsa_alu arithmetic (
        .a(alu_a),
        .b(alu_b),
        .subtract(subtract),
        .value(alu_value)
    );

    always @* begin
        alu_a = 0;
        alu_b = 0;
        subtract = 0;

        case (state)
            ADD: begin
                alu_a = {1'b0, accumulator};
                alu_b = {1'b0, x};
            end

            DOUBLE: begin
                alu_a = {1'b0, x};
                alu_b = {1'b0, x};
            end

            REDUCE_ADD, REDUCE_DOUBLE: begin
                alu_a = sum;
                alu_b = {1'b0, modulus};
                subtract = 1;
            end

            default: begin end
        endcase
    end

    // sum < 2*N, hence sum-N lies in (-2^28, 2^28).
    // Bit 28 identifies underflow under these invariants.
    wire [27:0] reduced =
        alu_value[28] ? sum[27:0] : alu_value[27:0];

    assign result = accumulator;

    // FINISH lasts one enabled clock cycle.
    assign done = (state == FINISH);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            x <= 0;
            y <= 0;
            accumulator <= 0;
            sum <= 0;
        end else if (ena) begin
            case (state)
                IDLE: if (start) begin
                    x <= a;
                    y <= b;
                    accumulator <= 0;
                    state <= CHECK;
                end

                CHECK: begin
                    if (y == 0)
                        state <= FINISH;
                    else if (y[0])
                        state <= ADD;
                    else
                        state <= DOUBLE;
                end

                ADD: begin
                    sum <= alu_value;
                    state <= REDUCE_ADD;
                end

                REDUCE_ADD: begin
                    accumulator <= reduced;
                    state <= DOUBLE;
                end

                DOUBLE: begin
                    sum <= alu_value;
                    state <= REDUCE_DOUBLE;
                end

                REDUCE_DOUBLE: begin
                    x <= reduced;
                    state <= SHIFT;
                end

                SHIFT: begin
                    y <= {1'b0, y[27:1]};
                    state <= CHECK;
                end

                FINISH: state <= IDLE;

                default: state <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire