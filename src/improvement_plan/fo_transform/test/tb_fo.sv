`default_nettype none
`timescale 1ns/1ps
module tb_fo;
    parameter integer WIDTH=42,SEED_BITS=14,COIN_BITS=14,MESSAGE_BITS=14,EXTERNAL_HASH=0;
    localparam integer HASH_BITS=(MESSAGE_BITS>COIN_BITS)?MESSAGE_BITS:COIN_BITS;
    localparam integer REQUEST_BITS=1+SEED_BITS+MESSAGE_BITS;
    localparam integer REQUEST_PAGES=(REQUEST_BITS+11)/12;
    localparam integer RESULT_BITS=WIDTH+MESSAGE_BITS,RESULT_PAGES=(RESULT_BITS+11)/12;
    localparam integer WORDS=(WIDTH+7)/7;
    localparam integer LIMIT=(4*WIDTH+4)*(WIDTH*(5*WORDS+4)+72)+4096;
    reg clk=0,rst_n=0,ena=1;
    reg [7:0] ui_in=0,uio_in=0;
    wire [7:0] uo_out,uio_out,uio_oe;
    integer fd,scanned,index,cycles,cases=0,sha_cases=0,hash_count=0,hash_calls=0;
    integer table_kind [0:4095];
    reg [SEED_BITS-1:0] table_seed [0:4095];
    reg [MESSAGE_BITS-1:0] table_message [0:4095];
    reg [HASH_BITS-1:0] table_value [0:4095];
    reg [6:0] command;
    reg [WIDTH-1:0] n,e,d,cipher;
    reg [SEED_BITS-1:0] seed;
    reg [MESSAGE_BITS-1:0] payload;
    reg expected_accept;
    reg [RESULT_BITS-1:0] expected;
    reg [6:0] first_command;
    reg [WIDTH-1:0] first_n,first_e,first_d,first_cipher;
    reg [SEED_BITS-1:0] first_seed;
    reg [MESSAGE_BITS-1:0] first_payload;
    reg first_accept;
    reg [RESULT_BITS-1:0] first_expected;
    reg sha_start=0;
    reg [511:0] sha_block;
    reg [255:0] sha_expected;
    wire [255:0] sha_digest;
    wire sha_done,sha_busy;
`ifdef GL_TEST
    // Allow standard-cell delays to settle; this is functional gate simulation.
    always #5000 clk=~clk;
    tt_um_rsa_fo dut (
        .VPWR(1'b1),.VGND(1'b0),
`else
    always #5 clk=~clk;
    tt_um_rsa_fo #(.WIDTH(WIDTH),.SEED_BITS(SEED_BITS),.COIN_BITS(COIN_BITS),
        .MESSAGE_BITS(MESSAGE_BITS),.EXTERNAL_HASH(EXTERNAL_HASH)) dut (
`endif
        .clk(clk),.rst_n(rst_n),.ena(ena),.ui_in(ui_in),.uio_in(uio_in),
        .uo_out(uo_out),.uio_out(uio_out),.uio_oe(uio_oe)
    );
`ifndef GL_TEST
    rsa_fo_sha256_block sha_unit (
        .clk(clk),.rst_n(rst_n),.ena(ena),.start(sha_start),.block(sha_block),
        .done(sha_done),.busy(sha_busy),.digest(sha_digest)
    );
`endif
    task ticks(input integer count); repeat(count) @(negedge clk); endtask
    task reset_chip;
        begin
            rst_n=0;ena=1;ui_in=0;uio_in=0;sha_start=0;ticks(4);
            if (uo_out!==0 || uio_out!==0 || uio_oe!==8'h7f)
                $fatal(1,"Incorrect GPIO reset state");
            rst_n=1;ticks(4);
        end
    endtask
    task control;
        begin uio_in[7]=1;ticks(4);uio_in[7]=0;ticks(4);end
    endtask
    task load_chunk(input [6:0] value);
        begin ui_in={1'b0,value};ticks(4);ui_in[7]=1;ticks(4);ui_in[7]=0;ticks(4);end
    endtask
    task load_operand(input [WIDTH-1:0] value);
        integer i;
        begin for(i=0;i<WIDTH/7;i=i+1) load_chunk((value>>(i*7))&7'h7f);end
    endtask
    task load_frame;
        integer i;
        begin
            load_chunk(command);
            if (uio_out[6]!==0 || uio_out[5]!==0) $fatal(1,"New frame did not clear status");
            control();
            if (uio_out[6]!==0) $fatal(1,"Premature START accepted");
            load_operand(n);load_operand(e);load_operand(d);load_operand(cipher);
            for(i=0;i<(SEED_BITS+6)/7;i=i+1) load_chunk((seed>>(i*7))&7'h7f);
            for(i=0;i<(MESSAGE_BITS+6)/7;i=i+1) load_chunk((payload>>(i*7))&7'h7f);
            load_chunk(7'h7f); // Complete-frame surplus input must be ignored.
        end
    endtask
    task service_hash;
        integer page,j,found;
        reg [REQUEST_PAGES*12-1:0] request;
        reg [SEED_BITS-1:0] requested_seed;
        reg [MESSAGE_BITS-1:0] requested_message;
        reg requested_kind;
        reg [HASH_BITS-1:0] response;
        begin
            if (!EXTERNAL_HASH) $fatal(1,"Unexpected host hash request in internal mode");
            request=0;
            for(page=0;page<REQUEST_PAGES;page=page+1) begin
                if (uio_out[5]!==1 || uio_out[6]!==0) $fatal(1,"Hash request was not held");
                request=request | ({{(REQUEST_PAGES*12-12){1'b0}},uio_out[3:0],uo_out}<<(page*12));
                if (page!=REQUEST_PAGES-1) control();
            end
            if (|(request>>REQUEST_BITS)) $fatal(1,"Nonzero hash-request padding");
            requested_seed=request[SEED_BITS-1:0];
            requested_message=request[SEED_BITS +: MESSAGE_BITS];
            requested_kind=request[SEED_BITS+MESSAGE_BITS];
            found=0;response=0;
            for(j=0;j<hash_count;j=j+1) begin
                if (table_kind[j]==requested_kind && table_seed[j]==requested_seed
                    && table_message[j]==requested_message) begin found=1;response=table_value[j];end
            end
            if (!found) $fatal(1,"Unexpected hash request kind=%d seed=%h message=%h",requested_kind,requested_seed,requested_message);
            ticks(5); // Model a host which needs time to calculate SHA-256.
            for(j=0;j<(HASH_BITS+6)/7;j=j+1) load_chunk((response>>(j*7))&7'h7f);
            hash_calls=hash_calls+1;
        end
    endtask
    task transaction;
        integer page,cycle;
        reg [RESULT_PAGES*12-1:0] actual;
        reg [7:0] saved_uio,saved_uo;
        begin
            load_frame();control();cycle=0;
            while(uio_out[6]!==1 && cycle<LIMIT) begin
                ticks(1);cycle=cycle+1;
                if (uio_out[5]===1) service_hash();
                else if (uio_out[6]!==1 && (uo_out!==0 || uio_out[3:0]!==0))
                    $fatal(1,"Data appeared on result channel before verification");
                if (cycle==3) begin
                    saved_uio=uio_out;saved_uo=uo_out;
                    ena=0;load_chunk(7'h55);control();
                    if (uio_out!==saved_uio || uo_out!==saved_uo) $fatal(1,"ena did not pause GPIO state");
                    ena=1;ticks(4);
                end
            end
            if (uio_out[6]!==1) $fatal(1,"FO timeout");
            if (uio_out[4] !== !expected_accept) $fatal(1,"Wrong ciphertext acceptance decision, case %d",cases);
            actual=0;
            for(page=0;page<RESULT_PAGES;page=page+1) begin
                actual=actual | ({{(RESULT_PAGES*12-12){1'b0}},uio_out[3:0],uo_out}<<(page*12));
                if(page!=RESULT_PAGES-1) control();
            end
            if (actual!=={{(RESULT_PAGES*12-RESULT_BITS){1'b0}},expected})
                $fatal(1,"FO case=%d expected=%h actual=%h",cases,expected,actual);
            saved_uio=uio_out;saved_uo=uo_out;
            control();ticks(6);
            if(uio_out!==saved_uio || uo_out!==saved_uo) $fatal(1,"Last result word or DONE changed");
            if(uio_oe!==8'h7f) $fatal(1,"Wrong GPIO directions");
            $display("FO_RESULT %0d %h %b",cases,actual,expected_accept);
            cases=cases+1;
        end
    endtask

    initial begin
        reset_chip();control();
        if(uio_out[6]!==0) $fatal(1,"START without frame accepted");
        fd=$fopen("fo_hashes.txt","r");
        if(!fd) $fatal(1,"Missing FO hash vectors");
        while(!$feof(fd)) begin
            if(hash_count>=4096) $fatal(1,"Hash fixture capacity exceeded");
            scanned=$fscanf(fd,"%h %h %h %h\n",table_kind[hash_count],table_seed[hash_count],
                table_message[hash_count],table_value[hash_count]);
            if(scanned!=4) $fatal(1,"Malformed hash vector");
            hash_count=hash_count+1;
        end
        $fclose(fd);
`ifndef GL_TEST
        fd=$fopen("sha_vectors.txt","r");
        if(!fd) $fatal(1,"Missing SHA-256 vectors");
        while(!$feof(fd)) begin
            scanned=$fscanf(fd,"%h %h\n",sha_block,sha_expected);
            if(scanned!=2) $fatal(1,"Malformed SHA-256 vector");
            sha_start=1;ticks(1);sha_start=0;cycles=0;
            while(sha_done!==1 && cycles<70) begin
                ticks(1);cycles=cycles+1;
                if(cycles==10) begin ena=0;ticks(5);ena=1;end
            end
            if(sha_done!==1 || sha_digest!==sha_expected)
                $fatal(1,"SHA-256 expected=%h got=%h",sha_expected,sha_digest);
            sha_cases=sha_cases+1;ticks(2);
        end
        $fclose(fd);
`endif
        fd=$fopen("fo_vectors.txt","r");
        if(!fd) $fatal(1,"Missing FO vectors");
        while(!$feof(fd)) begin
            scanned=$fscanf(fd,"%h %h %h %h %h %h %h %h %h\n",command,n,e,d,cipher,seed,payload,expected_accept,expected);
            if(scanned!=9) $fatal(1,"Malformed FO vector");
            if(cases==0) begin
                first_command=command;first_n=n;first_e=e;first_d=d;first_cipher=cipher;
                first_seed=seed;first_payload=payload;first_accept=expected_accept;first_expected=expected;
            end
            transaction();
        end
        $fclose(fd);
        // Reset aborts a pending hash operation or an unfinished packet.
        command=first_command;n=first_n;e=first_e;d=first_d;cipher=first_cipher;
        seed=first_seed;payload=first_payload;expected_accept=first_accept;expected=first_expected;
        load_frame();control();ticks(8);reset_chip();
        load_chunk(0);load_chunk(7'h12);reset_chip();
        transaction();
        if(EXTERNAL_HASH && hash_calls==0) $fatal(1,"External hash path was not exercised");
        $display("FO_PASS external=%0d cases=%0d sha=%0d",EXTERNAL_HASH,cases,sha_cases);
        $finish;
    end
endmodule
`default_nettype wire
