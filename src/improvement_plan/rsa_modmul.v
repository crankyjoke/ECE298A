`default_nettype none

module rsa_improved_modmul #(
    parameter integer WIDTH = 42,
    parameter integer WORD_BITS = 7
) (
    input  wire clk, rst_n, ena, start,
    input  wire [WIDTH-1:0] a, b, modulus,
    output wire [WIDTH-1:0] result,
    output wire done
);
    // Hold a,b,N stable until done; requires N>1 and 0<=a,b<N.
    // P = (2*P + b[i]*a) mod N, scanning b from MSB to LSB.
    // Each add/subtract rotates one processed word into the accumulator's top.
    // A full pass restores its orientation. Subtract N in place, then add N
    // back if the final borrow indicates P<N; no full-width trial-result bank.
    localparam integer WORDS = (WIDTH + 1 + WORD_BITS - 1) / WORD_BITS;
    localparam integer WORK_WIDTH = WORDS * WORD_BITS;
    localparam integer INDEX_BITS = (WIDTH > 1) ? $clog2(WIDTH) : 1;
    localparam integer WORD_INDEX_BITS = (WORDS > 1) ? $clog2(WORDS) : 1;
    localparam [3:0] IDLE=0, DOUBLE=1, SUB_DOUBLE=2, RESTORE_DOUBLE=3,
        CHECK_BIT=4, ADD=5, SUB_ADD=6, RESTORE_ADD=7, NEXT_BIT=8, FINISH=9;
    reg [3:0] state;
    reg [INDEX_BITS-1:0] bit_index;
    reg [WORD_INDEX_BITS-1:0] word_index;
    reg carry;
    reg [WORK_WIDTH-1:0] accumulator;
    wire subtract = (state == SUB_DOUBLE) || (state == SUB_ADD);
    wire word_operation = subtract || (state == ADD)
        || (state == RESTORE_DOUBLE) || (state == RESTORE_ADD);
    wire [WIDTH-1:0] operand = (state == ADD) ? a : modulus;
    wire [WORK_WIDTH-1:0] extended_operand =
        {{(WORK_WIDTH-WIDTH){1'b0}}, operand};
    reg [WORD_BITS-1:0] operand_word;
    integer selected_word;
    wire [WORD_BITS-1:0] alu_value;
    wire alu_carry;
    wire last_word = (word_index == WORDS-1);

    // Decode a word number directly. Shifting by word_index*WORD_BITS would
    // infer an unnecessarily general barrel shifter for non-power-of-two words.
    always @* begin
        operand_word = 0;
        for (selected_word = 0; selected_word < WORDS; selected_word = selected_word + 1)
            operand_word = operand_word
                | (extended_operand[selected_word*WORD_BITS +: WORD_BITS]
                    & {WORD_BITS{word_index == selected_word}});
    end

    rsa_improved_alu #(.WORD_BITS(WORD_BITS)) arithmetic (
        .a(accumulator[WORD_BITS-1:0]), .b(operand_word),
        .subtract(subtract), .carry_in(carry),
        .value(alu_value), .carry_out(alu_carry)
    );

    assign result = accumulator[WIDTH-1:0];
    assign done = (state == FINISH);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_index <= 0;
            word_index <= 0;
            carry <= 0;
        end else if (ena) begin
            case (state)
                IDLE: if (start) begin
                    bit_index <= WIDTH-1;
                    word_index <= 0;
                    carry <= 0;
                    state <= DOUBLE;
                end
                DOUBLE: begin
                    word_index <= 0;
                    carry <= 1;
                    state <= SUB_DOUBLE;
                end
                SUB_DOUBLE, SUB_ADD: begin
                    if (last_word) begin
                        word_index <= 0;
                        carry <= 0;
                        if (state == SUB_DOUBLE)
                            state <= alu_carry ? CHECK_BIT : RESTORE_DOUBLE;
                        else state <= alu_carry ? NEXT_BIT : RESTORE_ADD;
                    end else begin
                        word_index <= word_index + 1'b1;
                        carry <= alu_carry;
                    end
                end
                RESTORE_DOUBLE, RESTORE_ADD: begin
                    if (last_word) begin
                        word_index <= 0;
                        carry <= 0;
                        state <= (state == RESTORE_DOUBLE) ? CHECK_BIT : NEXT_BIT;
                    end else begin
                        word_index <= word_index + 1'b1;
                        carry <= alu_carry;
                    end
                end
                CHECK_BIT: begin
                    word_index <= 0;
                    carry <= 0;
                    state <= b[bit_index] ? ADD : NEXT_BIT;
                end
                ADD: begin
                    if (last_word) begin
                        word_index <= 0;
                        carry <= 1;
                        state <= SUB_ADD;
                    end else begin
                        word_index <= word_index + 1'b1;
                        carry <= alu_carry;
                    end
                end
                NEXT_BIT: begin
                    if (bit_index == 0) state <= FINISH;
                    else begin
                        bit_index <= bit_index - 1'b1;
                        state <= DOUBLE;
                    end
                end
                FINISH: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst_n && ena) begin
            if (state == IDLE && start) accumulator <= 0;
            else if (state == DOUBLE) accumulator <= accumulator << 1;
            else if (word_operation)
                accumulator <= {alu_value, accumulator[WORK_WIDTH-1:WORD_BITS]};
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (WIDTH < 2 || WORD_BITS < 1 || WORD_BITS > WIDTH)
            $fatal(1, "Invalid WIDTH or WORD_BITS");
    end
`endif
endmodule

`default_nettype wire
