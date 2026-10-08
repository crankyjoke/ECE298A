`default_nettype none

module rsa_loader (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ena,
    input  wire [7:0]  ui_in,
    input  wire        start_in,
    output reg  [27:0] modulus,
    output reg  [13:0] exponent,
    output reg  [13:0] message,
    output wire        start,
    output wire        page_select
);

    (* async_reg = "true" *) reg [7:0] ui_meta, ui_sync;
    (* async_reg = "true" *) reg start_meta, start_sync;

    reg load_prev, start_prev;
    reg [2:0] load_count;
    reg loaded;

    wire load_rise = ui_sync[7] & ~load_prev;
    wire start_rise = start_sync & ~start_prev;

    assign start = ena & loaded & start_rise;
    assign page_select = ui_sync[0];


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ui_meta <= 0;
            ui_sync <= 0;
            start_meta <= 0;
            start_sync <= 0;
            load_prev <= 0;
            start_prev <= 0;
        end else begin
            ui_meta <= ui_in;
            ui_sync <= ui_meta;
            start_meta <= start_in;
            start_sync <= start_meta;
            load_prev <= ui_sync[7];
            start_prev <= start_sync;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            modulus <= 0;
            exponent <= 0;
            message <= 0;
            load_count <= 0;
            loaded <= 0;
        end else if (ena && !loaded && load_rise) begin
            case (load_count)
                0: modulus[6:0] <= ui_sync[6:0];
                1: modulus[13:7] <= ui_sync[6:0];
                2: modulus[20:14] <= ui_sync[6:0];
                3: modulus[27:21] <= ui_sync[6:0];
                4: exponent[6:0] <= ui_sync[6:0];
                5: exponent[13:7] <= ui_sync[6:0];
                6: message[6:0] <= ui_sync[6:0];
                7: message[13:7] <= ui_sync[6:0];
            endcase

            if (load_count == 7)
                loaded <= 1;
            else
                load_count <= load_count + 3'd1;
        end
    end
endmodule

`default_nettype wire