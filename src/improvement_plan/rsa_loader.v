`default_nettype none

module rsa_improved_loader #(
    parameter integer WIDTH = 42
) (
    input  wire clk, rst_n, ena,
    input  wire [7:0] ui_in,
    input  wire start_in, busy, done,
    output reg  [WIDTH-1:0] modulus,
    output wire [6:0] load_data,
    output wire [1:0] load_field,
    output wire load, start, advance
);
    localparam integer CHUNKS = WIDTH / 7;
    localparam integer COUNT_BITS = (CHUNKS > 1) ? $clog2(CHUNKS) : 1;
    (* async_reg = "true" *) reg [6:0] data_meta, data_sync;
    (* async_reg = "true" *) reg load_meta, load_sync;
    (* async_reg = "true" *) reg start_meta, start_sync;
    reg load_prev, start_prev, loaded;
    reg [COUNT_BITS-1:0] chunk_count;
    reg [1:0] field;
    wire load_rise = load_sync && !load_prev;
    wire start_rise = start_sync && !start_prev;

    // N, e, m each occupy CHUNKS little-endian seven-bit transfers.
    assign load = ena && !busy && !loaded && load_rise;
    assign start = ena && !busy && loaded && !done && start_rise;
    // Once done, START is the result-word acknowledgement / advance strobe.
    assign advance = ena && done && start_rise && !load;
    assign load_data = data_sync;
    assign load_field = field;

    always @(posedge clk) begin
        data_meta <= ui_in[6:0];
        data_sync <= data_meta;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_meta <= 0;
            load_sync <= 0;
            start_meta <= 0;
            start_sync <= 0;
            load_prev <= 0;
            start_prev <= 0;
            loaded <= 0;
            chunk_count <= 0;
            field <= 0;
        end else begin
            // Synchronizers run even when the selected design is paused.
            load_meta <= ui_in[7];
            load_sync <= load_meta;
            start_meta <= start_in;
            start_sync <= start_meta;
            load_prev <= load_sync;
            start_prev <= start_sync;
            if (start) begin
                loaded <= 0;
                chunk_count <= 0;
                field <= 0;
            end else if (load) begin
                if (chunk_count == CHUNKS-1) begin
                    chunk_count <= 0;
                    if (field == 2) loaded <= 1;
                    else field <= field + 1'b1;
                end else chunk_count <= chunk_count + 1'b1;
            end
        end
    end

    // Every bit is overwritten before START; the operand needs no reset.
    // Shift right while loading least-significant chunks first.
    always @(posedge clk) begin
        if (rst_n && load && field == 0)
            modulus <= {load_data, modulus[WIDTH-1:7]};
    end

`ifndef SYNTHESIS
    initial begin
        if (WIDTH < 14 || WIDTH % 7 != 0)
            $fatal(1, "WIDTH must be at least 14 and a multiple of seven");
    end
`endif
endmodule

`default_nettype wire
