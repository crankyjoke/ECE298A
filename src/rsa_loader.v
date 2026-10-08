`default_nettype none
module rsa_loader (
    input wire clk, rst_n, ena,
    input wire [7:0] ui_in,
    input wire start_in,
    output reg [27:0] modulus,
    output wire [6:0] load_data,
    output wire [2:0] load_index,
    output wire load,
    output wire start, page_select
);
    // Hold bundled data stable before and throughout each LOAD pulse.
    (* async_reg = "true" *) reg [6:0] data_meta, data_sync;
    (* async_reg = "true" *) reg load_meta, load_sync;
    (* async_reg = "true" *) reg start_meta, start_sync;
    reg load_prev, start_prev;
    reg [2:0] load_count;
    reg loaded;
    wire load_rise = load_sync & ~load_prev;
    wire start_rise = start_sync & ~start_prev;
    wire capture = ena && !loaded && load_rise;
    assign start = ena & loaded & start_rise;
    assign page_select = data_sync[0];
    assign load_data = data_sync;
    assign load_index = load_count;
    assign load = capture;
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
            load_count <= 0;
            loaded <= 0;
        end else begin
            load_meta <= ui_in[7];
            load_sync <= load_meta;
            start_meta <= start_in;
            start_sync <= start_meta;
            load_prev <= load_sync;
            start_prev <= start_sync;
            if (capture) begin
                if (load_count == 7) loaded <= 1;
                else load_count <= load_count + 3'd1;
            end
        end
    end
    // All chunks are overwritten before computation, so no data reset.
    always @(posedge clk) begin
        if (rst_n && capture) begin
            case (load_count)
                0: modulus[6:0] <= data_sync;
                1: modulus[13:7] <= data_sync;
                2: modulus[20:14] <= data_sync;
                3: modulus[27:21] <= data_sync;
                default: begin end
            endcase
        end
    end
endmodule
`default_nettype wire
