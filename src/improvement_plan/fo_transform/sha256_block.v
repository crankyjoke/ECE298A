`default_nettype none

// One already-padded SHA-256 block, with the standard IV on every request.
// Digest byte order is the usual SHA-256 order: digest[255:248] is byte zero.
module rsa_fo_sha256_block (
    input wire clk, rst_n, ena, start,
    input wire [511:0] block,
    output wire busy,
    output reg done,
    output reg [255:0] digest
);
    reg running;
    reg [5:0] round_index;
    reg [31:0] a,b,c,d,e,f,g,h;
    reg [31:0] schedule [0:15];
    integer i;
    function [31:0] rotr;
        input [31:0] x;
        input integer n;
        begin rotr = (x >> n) | (x << (32-n)); end
    endfunction
    function [31:0] constant_k;
        input [5:0] index;
        begin
            case(index)
                 0:constant_k=32'h428a2f98;  1:constant_k=32'h71374491;
                 2:constant_k=32'hb5c0fbcf;  3:constant_k=32'he9b5dba5;
                 4:constant_k=32'h3956c25b;  5:constant_k=32'h59f111f1;
                 6:constant_k=32'h923f82a4;  7:constant_k=32'hab1c5ed5;
                 8:constant_k=32'hd807aa98;  9:constant_k=32'h12835b01;
                10:constant_k=32'h243185be; 11:constant_k=32'h550c7dc3;
                12:constant_k=32'h72be5d74; 13:constant_k=32'h80deb1fe;
                14:constant_k=32'h9bdc06a7; 15:constant_k=32'hc19bf174;
                16:constant_k=32'he49b69c1; 17:constant_k=32'hefbe4786;
                18:constant_k=32'h0fc19dc6; 19:constant_k=32'h240ca1cc;
                20:constant_k=32'h2de92c6f; 21:constant_k=32'h4a7484aa;
                22:constant_k=32'h5cb0a9dc; 23:constant_k=32'h76f988da;
                24:constant_k=32'h983e5152; 25:constant_k=32'ha831c66d;
                26:constant_k=32'hb00327c8; 27:constant_k=32'hbf597fc7;
                28:constant_k=32'hc6e00bf3; 29:constant_k=32'hd5a79147;
                30:constant_k=32'h06ca6351; 31:constant_k=32'h14292967;
                32:constant_k=32'h27b70a85; 33:constant_k=32'h2e1b2138;
                34:constant_k=32'h4d2c6dfc; 35:constant_k=32'h53380d13;
                36:constant_k=32'h650a7354; 37:constant_k=32'h766a0abb;
                38:constant_k=32'h81c2c92e; 39:constant_k=32'h92722c85;
                40:constant_k=32'ha2bfe8a1; 41:constant_k=32'ha81a664b;
                42:constant_k=32'hc24b8b70; 43:constant_k=32'hc76c51a3;
                44:constant_k=32'hd192e819; 45:constant_k=32'hd6990624;
                46:constant_k=32'hf40e3585; 47:constant_k=32'h106aa070;
                48:constant_k=32'h19a4c116; 49:constant_k=32'h1e376c08;
                50:constant_k=32'h2748774c; 51:constant_k=32'h34b0bcb5;
                52:constant_k=32'h391c0cb3; 53:constant_k=32'h4ed8aa4a;
                54:constant_k=32'h5b9cca4f; 55:constant_k=32'h682e6ff3;
                56:constant_k=32'h748f82ee; 57:constant_k=32'h78a5636f;
                58:constant_k=32'h84c87814; 59:constant_k=32'h8cc70208;
                60:constant_k=32'h90befffa; 61:constant_k=32'ha4506ceb;
                62:constant_k=32'hbef9a3f7; 63:constant_k=32'hc67178f2;
            endcase
        end
    endfunction
    wire [31:0] big0 = rotr(a,2) ^ rotr(a,13) ^ rotr(a,22);
    wire [31:0] big1 = rotr(e,6) ^ rotr(e,11) ^ rotr(e,25);
    wire [31:0] choose = (e & f) ^ (~e & g);
    wire [31:0] majority = (a & b) ^ (a & c) ^ (b & c);
    wire [31:0] t1 = h + big1 + choose + constant_k(round_index) + schedule[0];
    wire [31:0] t2 = big0 + majority;
    wire [31:0] new_word = (rotr(schedule[14],17) ^ rotr(schedule[14],19)
        ^ (schedule[14] >> 10)) + schedule[9]
        + (rotr(schedule[1],7) ^ rotr(schedule[1],18) ^ (schedule[1] >> 3))
        + schedule[0];
    assign busy = running;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin running<=0; round_index<=0; done<=0; digest<=0; end
        else if (ena) begin
            done <= 0;
            if (!running && start) begin
                round_index <= 0;
                running <= 1;
            end else if (running) begin
                if (round_index == 63) begin
                    digest <= {32'h6a09e667+(t1+t2),32'hbb67ae85+a,
                        32'h3c6ef372+b,32'ha54ff53a+c,32'h510e527f+(d+t1),
                        32'h9b05688c+e,32'h1f83d9ab+f,32'h5be0cd19+g};
                    running <= 0;
                    done <= 1;
                end else round_index <= round_index + 1'b1;
            end
        end
    end
    // Working data is overwritten at START. Keep it out of the async reset
    // process so synthesis does not infer ambiguous set/reset priorities.
    always @(posedge clk) begin
        if (rst_n && ena) begin
            if (!running && start) begin
                a<=32'h6a09e667; b<=32'hbb67ae85; c<=32'h3c6ef372; d<=32'ha54ff53a;
                e<=32'h510e527f; f<=32'h9b05688c; g<=32'h1f83d9ab; h<=32'h5be0cd19;
                for(i=0;i<16;i=i+1) schedule[i] <= block[511-i*32 -: 32];
            end else if (running) begin
                a<=t1+t2; b<=a; c<=b; d<=c; e<=d+t1; f<=e; g<=f; h<=g;
                for(i=0;i<15;i=i+1) schedule[i] <= schedule[i+1];
                schedule[15] <= new_word;
            end
        end
    end
endmodule
`default_nettype wire
