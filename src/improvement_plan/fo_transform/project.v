`default_nettype none

// GPIO top for the experimental hybrid FO profile. See this folder's README.
// Default hashes on-chip with Keccak25-7; SMALL_HASH=0 selects SHA-256.
module tt_um_rsa_fo #(
    parameter integer WIDTH=28, WORD_BITS=7,
    parameter integer SEED_BITS=7, COIN_BITS=7, MESSAGE_BITS=7,
    parameter integer EXTERNAL_HASH=0, SMALL_HASH=1
) (
    input wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input wire [7:0] uio_in,
    output wire [7:0] uio_out, uio_oe,
    input wire ena, clk, rst_n
);
    localparam integer CHUNKS=WIDTH/7, SEED_CHUNKS=(SEED_BITS+6)/7;
    localparam integer MESSAGE_CHUNKS=(MESSAGE_BITS+6)/7;
    localparam integer HASH_BITS=(MESSAGE_BITS>COIN_BITS)?MESSAGE_BITS:COIN_BITS;
    localparam integer HASH_CHUNKS=(HASH_BITS+6)/7;
    localparam integer SEED_PAD=SEED_CHUNKS*7, MESSAGE_PAD=MESSAGE_CHUNKS*7;
    localparam integer HASH_PAD=HASH_CHUNKS*7;
    localparam integer MAX_CHUNKS=(CHUNKS>SEED_CHUNKS)?
        ((CHUNKS>MESSAGE_CHUNKS)?CHUNKS:MESSAGE_CHUNKS):
        ((SEED_CHUNKS>MESSAGE_CHUNKS)?SEED_CHUNKS:MESSAGE_CHUNKS);
    localparam integer COUNT_BITS=(MAX_CHUNKS>1)?$clog2(MAX_CHUNKS):1;
    localparam integer HASH_COUNT_BITS=(HASH_CHUNKS>1)?$clog2(HASH_CHUNKS):1;
    localparam integer REQUEST_BITS=1+SEED_BITS+MESSAGE_BITS;
    localparam integer RESULT_BITS=WIDTH+MESSAGE_BITS;
    localparam integer REQUEST_PAGES=(REQUEST_BITS+11)/12, RESULT_PAGES=(RESULT_BITS+11)/12;
    localparam integer MAX_PAGES=(REQUEST_PAGES>RESULT_PAGES)?REQUEST_PAGES:RESULT_PAGES;
    localparam integer PAGE_BITS=(MAX_PAGES>1)?$clog2(MAX_PAGES):1;
    (* async_reg="true" *) reg [6:0] data_meta,data_sync;
    (* async_reg="true" *) reg load_meta,load_sync,control_meta,control_sync;
    reg load_prev,control_prev,loaded,decrypting,frame_error;
    reg [2:0] field;
    reg [COUNT_BITS-1:0] chunk_index;
    reg [WIDTH-1:0] modulus,public_exponent,private_exponent,ciphertext;
    reg [SEED_PAD-1:0] seed_input;
    reg [MESSAGE_PAD-1:0] payload_input;
    wire [SEED_PAD-1:0] seed_chunk=data_sync;
    wire [MESSAGE_PAD-1:0] payload_chunk=data_sync;
    wire [HASH_PAD-1:0] hash_chunk=data_sync;
    wire load_rise=load_sync && !load_prev;
    wire control_rise=control_sync && !control_prev;
    wire engine_busy,engine_done,rejected,accepted;
    wire hash_req_valid,hash_req_kind,hash_resp_ready;
    wire [SEED_BITS-1:0] hash_req_seed;
    wire [MESSAGE_BITS-1:0] hash_req_message;
    reg hash_pending,hash_resp_valid;
    reg [HASH_PAD-1:0] response_shift;
    reg [HASH_COUNT_BITS-1:0] hash_chunk_index;
    wire hash_req_ready=ena && !hash_pending && !hash_resp_valid;
    wire hash_accept=hash_req_valid && hash_req_ready;
    wire capture=ena && !engine_busy && !loaded && !hash_pending && load_rise;
    wire clear_engine=capture && field==0;
    wire engine_start=ena && loaded && !engine_busy && !engine_done && control_rise;
    wire malformed=frame_error || (|(seed_input >> SEED_BITS)) || (|(payload_input >> MESSAGE_BITS));
    wire [WIDTH-1:0] output_cipher;
    wire [MESSAGE_BITS-1:0] output_masked,output_plaintext;
    reg [PAGE_BITS-1:0] page_index;
    wire [RESULT_BITS-1:0] result_data=decrypting ?
        {{WIDTH{1'b0}},output_plaintext}:{output_masked,output_cipher};
    // FO holds these operands through the response; do not duplicate their banks.
    wire [REQUEST_BITS-1:0] request_data={hash_req_kind,hash_req_message,hash_req_seed};
    wire [MAX_PAGES*12-1:0] result_padded=result_data;
    wire [MAX_PAGES*12-1:0] request_padded=request_data;
    reg [11:0] output_word;
    integer page;

    rsa_fo_engine #(.WIDTH(WIDTH),.WORD_BITS(WORD_BITS),.SEED_BITS(SEED_BITS),
        .COIN_BITS(COIN_BITS),.MESSAGE_BITS(MESSAGE_BITS),.EXTERNAL_HASH(EXTERNAL_HASH),
        .SMALL_HASH(SMALL_HASH)) engine (
        .clk(clk),.rst_n(rst_n),.ena(ena),.clear(clear_engine),.start(engine_start),
        .decrypt(decrypting),.modulus(modulus),
        .public_exponent(malformed?{WIDTH{1'b0}}:public_exponent),
        .private_exponent(private_exponent),.ciphertext_in(ciphertext),
        .random_seed(seed_input[SEED_BITS-1:0]),.payload(payload_input[MESSAGE_BITS-1:0]),
        .busy(engine_busy),.done(engine_done),.rejected(rejected),.accepted(accepted),
        .ciphertext_out(output_cipher),.masked_out(output_masked),.plaintext_out(output_plaintext),
        .hash_request_valid(hash_req_valid),.hash_request_kind(hash_req_kind),
        .hash_request_seed(hash_req_seed),.hash_request_message(hash_req_message),
        .hash_request_ready(hash_req_ready),.hash_response_valid(hash_resp_valid),
        .hash_response_value(response_shift[HASH_BITS-1:0]),.hash_response_ready(hash_resp_ready)
    );

    always @(posedge clk) begin data_meta<=ui_in[6:0]; data_sync<=data_meta; end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_meta<=0;load_sync<=0;control_meta<=0;control_sync<=0;
            load_prev<=0;control_prev<=0;loaded<=0;field<=0;chunk_index<=0;
            decrypting<=0;frame_error<=0;
        end else begin
            load_meta<=ui_in[7];load_sync<=load_meta;
            control_meta<=uio_in[7];control_sync<=control_meta;
            load_prev<=load_sync;control_prev<=control_sync;
            if (engine_start) begin loaded<=0;field<=0;chunk_index<=0;end
            else if (capture) begin
                if (field==0) begin
                    decrypting<=data_sync[0];frame_error<=|data_sync[6:1];
                    field<=1;chunk_index<=0;
                end else if ((field==5 && chunk_index==SEED_CHUNKS-1)
                    || (field==6 && chunk_index==MESSAGE_CHUNKS-1)
                    || (field<5 && chunk_index==CHUNKS-1)) begin
                    chunk_index<=0;
                    if (field==6) loaded<=1;
                    else field<=field+1'b1;
                end else chunk_index<=chunk_index+1'b1;
            end
        end
    end
    always @(posedge clk) begin
        if (rst_n && capture) case(field)
            1:modulus<={data_sync,modulus[WIDTH-1:7]};
            2:public_exponent<={data_sync,public_exponent[WIDTH-1:7]};
            3:private_exponent<={data_sync,private_exponent[WIDTH-1:7]};
            4:ciphertext<={data_sync,ciphertext[WIDTH-1:7]};
            5:seed_input<=(seed_input>>7)|(seed_chunk<<(SEED_PAD-7));
            6:payload_input<=(payload_input>>7)|(payload_chunk<<(MESSAGE_PAD-7));
            default:begin end
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin hash_pending<=0;hash_resp_valid<=0;hash_chunk_index<=0;end
        else if (ena) begin
            if (hash_accept) begin
                hash_pending<=1;
                hash_chunk_index<=0;
            end
            if (hash_pending && !hash_resp_valid && load_rise) begin
                if (hash_chunk_index==HASH_CHUNKS-1) begin
                    hash_resp_valid<=1;hash_chunk_index<=0;
                end else hash_chunk_index<=hash_chunk_index+1'b1;
            end
            if (hash_resp_valid && hash_resp_ready) begin hash_resp_valid<=0;hash_pending<=0;end
        end
    end
    always @(posedge clk) begin
        if (rst_n && ena && hash_pending && !hash_resp_valid && load_rise)
            response_shift<=(response_shift>>7)|(hash_chunk<<(HASH_PAD-7));
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) page_index<=0;
        else if (ena) begin
            if (clear_engine || hash_accept || (!engine_done && !hash_pending)) page_index<=0;
            else if (control_rise) begin
                if (hash_pending && page_index<REQUEST_PAGES-1) page_index<=page_index+1'b1;
                else if (engine_done && page_index<RESULT_PAGES-1) page_index<=page_index+1'b1;
            end
        end
    end
    always @* begin
        output_word=0;
        for(page=0;page<MAX_PAGES;page=page+1)
            output_word=output_word | ((hash_pending?request_padded[page*12 +:12]:result_padded[page*12 +:12])
                & {12{page_index==page}});
        if (!engine_done && !hash_pending) output_word=0;
    end
    assign uo_out=output_word[7:0];
    assign uio_out={1'b0,engine_done,hash_pending,rejected,output_word[11:8]};
    assign uio_oe=8'h7f;
endmodule
`default_nettype wire
