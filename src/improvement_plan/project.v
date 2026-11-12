`default_nettype none

// Experimental Tiny Tapeout top. This has a different protocol from project.v.
module tt_um_rsa_improved #(
    parameter integer WIDTH = 42,
    parameter integer WORD_BITS = 7
) (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena, clk, rst_n
);
    localparam integer PAGES = (WIDTH + 13) / 14;
    localparam integer PAGE_BITS = (PAGES > 1) ? $clog2(PAGES) : 1;
    wire [WIDTH-1:0] modulus, result;
    wire [6:0] load_data;
    wire [1:0] load_field;
    wire load, start, advance, busy, done;
    reg [PAGE_BITS-1:0] page_index;
    wire [PAGES*14-1:0] padded_result = {{(PAGES*14-WIDTH){1'b0}}, result};
    reg [13:0] page;
    integer selected_page;

    always @* begin
        page = 0;
        for (selected_page = 0; selected_page < PAGES; selected_page = selected_page + 1)
            page = page | (padded_result[selected_page*14 +: 14]
                & {14{page_index == selected_page}});
    end

    rsa_improved_loader #(.WIDTH(WIDTH)) loader (
        .clk(clk), .rst_n(rst_n), .ena(ena), .ui_in(ui_in),
        .start_in(uio_in[7]), .busy(busy), .done(done),
        .modulus(modulus), .load_data(load_data), .load_field(load_field),
        .load(load), .start(start), .advance(advance)
    );
    rsa_improved_modexp #(.WIDTH(WIDTH), .WORD_BITS(WORD_BITS)) exponentiation (
        .clk(clk), .rst_n(rst_n), .ena(ena), .start(start),
        .modulus(modulus), .load(load), .load_field(load_field),
        .load_data(load_data), .result(result), .busy(busy), .done(done)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) page_index <= 0;
        else if (ena) begin
            if (!done || load) page_index <= 0;
            else if (advance && page_index < PAGES-1)
                page_index <= page_index + 1'b1;
        end
    end

    assign uo_out = done ? page[7:0] : 8'b0;
    assign uio_out = {1'b0, done, (done ? page[13:8] : 6'b0)};
    assign uio_oe = 8'h7f;
endmodule

`default_nettype wire
