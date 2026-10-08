`default_nettype none
module rsa_modmul (
    input wire clk, rst_n, ena, start,
    input wire [27:0] a, b, modulus,
    output wire [27:0] result,
    output wire done
);
    // Hold a, b, modulus stable through done; a,b < modulus.
    // MSB-first multiplication: P = (2*P + b[i]*a) mod N.
    localparam [2:0] IDLE=0, DOUBLE=1, REDUCE_DOUBLE=2,
        CHECK_BIT=3, ADD=4, REDUCE_ADD=5, NEXT_BIT=6, FINISH=7;
    reg [2:0] state;
    reg [4:0] bit_index;
    reg [28:0] accumulator;
    wire reducing = (state == REDUCE_ADD) || (state == REDUCE_DOUBLE);
    wire [28:0] alu_a = accumulator;
    wire [28:0] alu_b = reducing ? {1'b0, modulus} :
        (state == DOUBLE) ? accumulator : {1'b0, a};
    wire [28:0] alu_value;
    rsa_alu arithmetic (.a(alu_a), .b(alu_b),
        .subtract(reducing), .value(alu_value));
    // Before reduction, accumulator < 2*N.
    // Bit 28 of accumulator-N therefore identifies underflow.
    wire [27:0] reduced = alu_value[28] ? accumulator[27:0] : alu_value[27:0];
    assign result = accumulator[27:0];
    assign done = (state == FINISH);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else if (ena) begin
            case (state)
                IDLE: if (start) state <= DOUBLE;
                DOUBLE: state <= REDUCE_DOUBLE;
                REDUCE_DOUBLE: state <= CHECK_BIT;
                CHECK_BIT: state <= b[bit_index] ? ADD : NEXT_BIT;
                ADD: state <= REDUCE_ADD;
                REDUCE_ADD: state <= NEXT_BIT;
                NEXT_BIT: state <= (bit_index == 0) ? FINISH : DOUBLE;
                FINISH: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
    // Data registers are initialized before use; no reset cells needed.
    always @(posedge clk) begin
        if (rst_n && ena) begin
            case (state)
                IDLE: if (start) begin
                    accumulator <= 0;
                    bit_index <= 5'd27;
                end
                DOUBLE, ADD: accumulator <= alu_value;
                REDUCE_DOUBLE, REDUCE_ADD: accumulator <= {1'b0, reduced};
                NEXT_BIT: if (bit_index != 0) bit_index <= bit_index - 5'd1;
                default: begin end
            endcase
        end
    end
endmodule
`default_nettype wire
