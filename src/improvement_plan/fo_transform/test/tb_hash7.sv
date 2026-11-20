`default_nettype none
`timescale 1ns/1ps
module tb_hash7;
    reg clk=0,rst_n=0,ena=1,request_valid=0,kind=0,response_ready=0;
    reg [6:0] seed=0,message=0;
    wire request_ready,response_valid;
    wire [6:0] value;
    integer fd,scanned,k,s,m,expected,cases=0,cycles;
    reg [6:0] held;
    always #5 clk=~clk;
    rsa_fo_tiny_hash7 dut (
        .clk(clk),.rst_n(rst_n),.ena(ena),.request_valid(request_valid),
        .request_kind(kind),.request_seed(seed),.request_message(message),
        .request_ready(request_ready),.response_valid(response_valid),
        .response_value(value),.response_ready(response_ready)
    );
    task ticks(input integer count);repeat(count) @(negedge clk);endtask
    task reset_hash;
        begin
            rst_n=0;ena=1;request_valid=0;response_ready=0;ticks(2);
            if(response_valid!==0||request_ready!==1) $fatal(1,"Bad hash reset state");
            rst_n=1;ticks(1);
        end
    endtask
    task check_hash(input integer kk,ss,mm,wanted);
        begin
            if(request_ready!==1) $fatal(1,"Hash did not rearm");
            kind=kk;seed=ss;message=mm;request_valid=1;ticks(1);request_valid=0;
            // Requests must be latched: change every input immediately afterward.
            kind=!kk;seed=~ss;message=~mm;
            cycles=0;
            while(response_valid!==1&&cycles<40) begin
                if(request_ready!==0) $fatal(1,"Hash accepted a busy request");
                ticks(1);cycles=cycles+1;
                if(cycles==3&&(cases&255)==0) begin
                    ena=0;request_valid=1;ticks(5);request_valid=0;ena=1;
                end
            end
            if(response_valid!==1||value!==wanted[6:0]||cycles!=(kk?36:24))
                $fatal(1,"Hash k=%0d s=%0d m=%0d expected=%h got=%h cycles=%0d",kk,ss,mm,wanted,value,cycles);
            held=value;ticks(2);
            if(response_valid!==1||value!==held) $fatal(1,"Hash response not held");
            if((cases&255)==0) begin
                ena=0;response_ready=1;ticks(3);
                if(response_valid!==1||value!==held) $fatal(1,"ena did not pause response");
                response_ready=0;ena=1;
            end
            response_ready=1;ticks(1);response_ready=0;
            if(response_valid!==0) $fatal(1,"Hash response not consumed");
            cases=cases+1;
        end
    endtask
    initial begin
        reset_hash();
        kind=1;seed=5;message=77;request_valid=1;ticks(1);request_valid=0;
        ticks(8);reset_hash(); // Reset aborts an in-progress permutation.
        fd=$fopen("hash7_vectors.txt","r");
        if(!fd) $fatal(1,"Missing exhaustive hash vectors");
        while(!$feof(fd)) begin
            scanned=$fscanf(fd,"%h %h %h %h\n",k,s,m,expected);
            if(scanned!=4) $fatal(1,"Malformed hash vector");
            check_hash(k,s,m,expected);
        end
        $fclose(fd);
        reset_hash();check_hash(k,s,m,expected);
        $display("HASH7_PASS cases=%0d",cases);$finish;
    end
endmodule
`default_nettype wire
