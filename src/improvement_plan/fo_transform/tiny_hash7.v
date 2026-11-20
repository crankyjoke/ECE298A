`default_nettype none

// Repository's educational Keccak25-7 sponge, NOT SHA-3 or SHAKE.
// Keccak-f[25], all 12 rounds; rate=7, capacity=18, output=7 bits.
// Absorb LSB-first: kind || seed[0..6] || (kind ? message[0..6] : empty),
// then pad10*1 to a multiple of seven. G ignores message. See README.
module rsa_fo_tiny_hash7 (
    input wire clk, rst_n, ena,
    input wire request_valid, request_kind,
    input wire [6:0] request_seed, request_message,
    output wire request_ready, response_valid,
    output wire [6:0] response_value,
    input wire response_ready
);
    localparam [1:0] IDLE=0, RUNNING=1, RESPONSE=2;
    reg [1:0] state, blocks_left;
    reg [3:0] round_index;
    reg [24:0] sponge;
    reg [13:0] remaining;
    wire [20:0] frame=request_kind ?
        {1'b1,4'b0,1'b1,request_message,request_seed,1'b1} :
        {7'b0,1'b1,4'b0,1'b1,request_seed,1'b0};
    reg round_constant;
    reg [4:0] parity;
    reg [24:0] theta, rho_pi, chi;
    wire [24:0] next_round=chi ^ {24'b0,round_constant};
    integer x,y;

    // State index x+5*y; each lane is one bit, so all lane rotations are zero.
    // Round constants are the low bits of Keccak's first twelve constants.
    always @* begin
        case(round_index)
            0,4,5,6,7,10:round_constant=1'b1;
            default:round_constant=1'b0;
        endcase
        for(x=0;x<5;x=x+1)
            parity[x]=sponge[x]^sponge[x+5]^sponge[x+10]^sponge[x+15]^sponge[x+20];
        for(y=0;y<5;y=y+1)
            for(x=0;x<5;x=x+1)
                theta[x+5*y]=sponge[x+5*y]^parity[(x+4)%5]^parity[(x+1)%5];
        for(y=0;y<5;y=y+1)
            for(x=0;x<5;x=x+1)
                rho_pi[y+5*((2*x+3*y)%5)]=theta[x+5*y];
        for(y=0;y<5;y=y+1)
            for(x=0;x<5;x=x+1)
                chi[x+5*y]=rho_pi[x+5*y]^
                    ((~rho_pi[(x+1)%5+5*y])&rho_pi[(x+2)%5+5*y]);
    end
    assign request_ready=(state==IDLE)&&ena;
    assign response_valid=(state==RESPONSE);
    assign response_value=sponge[6:0];

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin state<=IDLE;round_index<=0;blocks_left<=0;end
        else if(ena) case(state)
            IDLE:if(request_valid) begin
                state<=RUNNING;round_index<=0;blocks_left<=request_kind?2:1;
            end
            RUNNING:if(round_index==11) begin
                round_index<=0;
                if(blocks_left!=0) blocks_left<=blocks_left-1'b1;
                else state<=RESPONSE;
            end else round_index<=round_index+1'b1;
            RESPONSE:if(response_ready) state<=IDLE;
            default:state<=IDLE;
        endcase
    end
    // Request data is captured at acceptance; callers may change it afterward.
    always @(posedge clk) begin
        if(rst_n&&ena) begin
            if(state==IDLE&&request_valid) begin
                sponge<={18'b0,frame[6:0]};remaining<=frame[20:7];
            end else if(state==RUNNING) begin
                if(round_index==11&&blocks_left!=0) begin
                    sponge<=next_round^{18'b0,remaining[6:0]};
                    remaining<={7'b0,remaining[13:7]};
                end else sponge<=next_round;
            end
        end
    end
endmodule
`default_nettype wire
