class transaction;

    rand bit operation;        // Renamed oper to operation
    bit rd, wr;
    bit [7:0] din;             // Renamed data_in to din
    bit full, empty;
    bit [7:0] dout;            // Renamed data_out to dout

    constraint operation_ctrl {  
        operation dist {1 :/ 50, 0 :/ 50};  // Renamed oper_ctrl to operation_ctrl
    }

endclass

class generator;

    transaction tr;
    mailbox #(transaction) mbx;
    int count = 0;
    int iteration = 0;         // Renamed i to iteration

    event next;  
    event done;

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
        tr = new();
    endfunction; 

    task run(); 
        repeat (count) begin
            assert (tr.randomize) else $error("Randomization failed");
            iteration++;
            mbx.put(tr);
            $display("[GEN] : Operation: %0d Iteration: %0d", tr.operation, iteration);
            @(next);
        end
        -> done;
    endtask

endclass

class driver;

    virtual fifo_if fif;
    mailbox #(transaction) mbx;
    transaction tr;            // Renamed datac to tr

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction; 

    task reset();
        fif.rst <= 1'b1;
        fif.rd <= 1'b0;
        fif.wr <= 1'b0;
        fif.din <= 0;
        repeat (5) @(posedge fif.clk);
        fif.rst <= 1'b0;
        $display("[DRV] : DUT Reset Done");
        $display("------------------------------------------");
    endtask

    task write();
        @(posedge fif.clk);
        fif.rst <= 1'b0;
        fif.rd <= 1'b0;
        fif.wr <= 1'b1;
        fif.din <= $urandom_range(1, 10);
        @(posedge fif.clk);
        fif.wr <= 1'b0;
        $display("[DRV] : DATA WRITE  data: %0d", fif.din);  
        @(posedge fif.clk);
    endtask

    task read();  
        @(posedge fif.clk);
        fif.rst <= 1'b0;
        fif.rd <= 1'b1;
        fif.wr <= 1'b0;
        @(posedge fif.clk);
        fif.rd <= 1'b0;      
        $display("[DRV] : DATA READ");  
        @(posedge fif.clk);
    endtask

    task run();
        forever begin
            mbx.get(tr);  
            if (tr.operation == 1'b1)
                write();
            else
                read();
        end
    endtask

endclass

class monitor;

    virtual fifo_if fif;
    mailbox #(transaction) mbx;
    transaction tr;

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;     
    endfunction;

    task run();
        tr = new();

        forever begin
            repeat (2) @(posedge fif.clk);
            tr.wr = fif.wr;
            tr.rd = fif.rd;
            tr.din = fif.din;
            tr.full = fif.full;
            tr.empty = fif.empty; 
            @(posedge fif.clk);
            tr.dout = fif.dout;

            mbx.put(tr);
            $display("[MON] : Wr: %0d Rd: %0d Din: %0d Dout: %0d Full: %0d Empty: %0d", 
                     tr.wr, tr.rd, tr.din, tr.dout, tr.full, tr.empty);
        end

    endtask

endclass

class scoreboard;

    mailbox #(transaction) mbx;
    transaction tr;
    event next;
    bit [7:0] input_queue[$];  // Renamed din to input_queue
    bit [7:0] temp;
    int errors = 0;            // Renamed err to errors

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;     
    endfunction;

    task run();
        forever begin
            mbx.get(tr);
            $display("[SCO] : Wr: %0d Rd: %0d Din: %0d Dout: %0d Full: %0d Empty: %0d", 
                     tr.wr, tr.rd, tr.din, tr.dout, tr.full, tr.empty);

            if (tr.wr == 1'b1) begin
                if (tr.full == 1'b0) begin
                    input_queue.push_front(tr.din);
                    $display("[SCO] : Data Stored: %0d", tr.din);
                end
                else begin
                    $display("[SCO] : FIFO is full");
                end
                $display("--------------------------------------"); 
            end

            if (tr.rd == 1'b1) begin
                if (tr.empty == 1'b0) begin  
                    temp = input_queue.pop_back();
                    if (tr.dout == temp)
                        $display("[SCO] : Data Match");
                    else begin
                        $error("[SCO] : Data Mismatch");
                        errors++;
                    end
                end
                else begin
                    $display("[SCO] : FIFO is empty");
                end
                $display("--------------------------------------"); 
            end

            -> next;
        end
    endtask

endclass

class environment;

    generator gen;
    driver drv;
    monitor mon;
    scoreboard sco;
    mailbox #(transaction) gen_drv_mbx;
    mailbox #(transaction) mon_sco_mbx;
    event next_event;
    virtual fifo_if fif;

    function new(virtual fifo_if fif);
        gen_drv_mbx = new();
        gen = new(gen_drv_mbx);
        drv = new(gen_drv_mbx);
        mon_sco_mbx = new();
        mon = new(mon_sco_mbx);
        sco = new(mon_sco_mbx);
        this.fif = fif;
        drv.fif = this.fif;
        mon.fif = this.fif;
        gen.next = next_event;
        sco.next = next_event;
    endfunction

    task pre_test();
        drv.reset();
    endtask

    task test();
        fork
            gen.run();
            drv.run();
            mon.run();
            sco.run();
        join_any
    endtask

    task post_test();
        wait(gen.done.triggered);  
        $display("---------------------------------------------");
        $display("Error Count: %0d", sco.errors);
        $display("---------------------------------------------");
        $finish();
    endtask

    task run();
        pre_test();
        test();
        post_test();
    endtask

endclass

module tb;

    fifo_if fif();
    FIFO dut(fif.clk, fif.rst, fif.wr, fif.rd, fif.din, fif.dout, fif.empty, fif.full);

    initial begin
        fif.clk <= 0;
    end

    always #10 fif.clk <= ~fif.clk;

    environment env;

    initial begin
        env = new(fif);
        env.gen.count = 10;
        env.run();
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end

endmodule
