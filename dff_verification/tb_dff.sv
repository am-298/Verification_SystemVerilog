class data_packet;
  rand bit in_data;
  bit out_data;
  
  function data_packet clone();
    clone = new();
    clone.in_data = this.in_data;
    clone.out_data = this.out_data;
  endfunction
  
  function void show(input string label);
    $display("[%0s] : IN : %0b OUT : %0b", label, in_data, out_data);
  endfunction
endclass

//////////////////////////////////////////////////

class stimulus_gen;
  data_packet pkt;
  mailbox #(data_packet) driver_mbx;
  mailbox #(data_packet) scoreboard_mbx;
  event score_done;
  event gen_done;
  int num_stimuli;

  function new(mailbox #(data_packet) driver_mbx, mailbox #(data_packet) scoreboard_mbx);
    this.driver_mbx = driver_mbx;
    this.scoreboard_mbx = scoreboard_mbx;
    pkt = new();
  endfunction
  
  task execute();
    repeat(num_stimuli) begin
      assert(pkt.randomize) else $error("[GEN] : RANDOMIZATION FAILED");
      driver_mbx.put(pkt.clone());
      scoreboard_mbx.put(pkt.clone());
      pkt.show("GEN");
      @(score_done);
    end
    ->gen_done;
  endtask
  
endclass

//////////////////////////////////////////////////////////

class data_driver;
  data_packet pkt;
  mailbox #(data_packet) driver_mbx;
  virtual flipflop_if vif_if;
  
  function new(mailbox #(data_packet) driver_mbx);
    this.driver_mbx = driver_mbx;
  endfunction
  
  task reset();
    vif_if.rst_sig <= 1'b1;
    repeat(5) @(posedge vif_if.clk_sig);
    vif_if.rst_sig <= 1'b0;
    @(posedge vif_if.clk_sig);
    $display("[DRV] : RESET COMPLETE");
  endtask
  
  task execute();
    forever begin
      driver_mbx.get(pkt);
      vif_if.in_sig <= pkt.in_data;
      @(posedge vif_if.clk_sig);
      pkt.show("DRV");
      vif_if.in_sig <= 1'b0;
      @(posedge vif_if.clk_sig);
    end
  endtask
  
endclass

//////////////////////////////////////////////////////

class data_monitor;
  data_packet pkt;
  mailbox #(data_packet) monitor_mbx;
  virtual flipflop_if vif_if;
  
  function new(mailbox #(data_packet) monitor_mbx);
    this.monitor_mbx = monitor_mbx;
  endfunction
  
  task execute();
    pkt = new();
    forever begin
      repeat(2) @(posedge vif_if.clk_sig);
      pkt.out_data = vif_if.out_sig;
      monitor_mbx.put(pkt);
      pkt.show("MON");
    end
  endtask
  
endclass

////////////////////////////////////////////////////

class result_checker;
  data_packet pkt;
  data_packet ref_pkt;
  mailbox #(data_packet) monitor_mbx;
  mailbox #(data_packet) ref_mbx;
  event score_done;

  function new(mailbox #(data_packet) monitor_mbx, mailbox #(data_packet) ref_mbx);
    this.monitor_mbx = monitor_mbx;
    this.ref_mbx = ref_mbx;
  endfunction
  
  task execute();
    forever begin
      monitor_mbx.get(pkt);
      ref_mbx.get(ref_pkt);
      pkt.show("SCO");
      ref_pkt.show("REF");
      if (pkt.out_data == ref_pkt.in_data)
        $display("[SCO] : DATA MATCHED");
      else
        $display("[SCO] : DATA MISMATCHED");
      $display("-----------------------------------------------");
      ->score_done;
    end
  endtask
  
endclass

////////////////////////////////////////////////////////

class verification_env;
  stimulus_gen stim;
  data_driver drv;
  data_monitor mon;
  result_checker sco;
  event next_evt;

  mailbox #(data_packet) stim_drv_mbx;
  mailbox #(data_packet) mon_sco_mbx;
  mailbox #(data_packet) ref_mbx;

  virtual flipflop_if vif_if;

  function new(virtual flipflop_if vif_if);
    stim_drv_mbx = new();
    ref_mbx = new();
    stim = new(stim_drv_mbx, ref_mbx);
    drv = new(stim_drv_mbx);
    mon_sco_mbx = new();
    mon = new(mon_sco_mbx);
    sco = new(mon_sco_mbx, ref_mbx);
    this.vif_if = vif_if;
    drv.vif_if = this.vif_if;
    mon.vif_if = this.vif_if;
    stim.score_done = next_evt;
    sco.score_done = next_evt;
  endfunction
  
  task setup();
    drv.reset();
  endtask
  
  task run_test();
    fork
      stim.execute();
      drv.execute();
      mon.execute();
      sco.execute();
    join_any
  endtask
  
  task cleanup();
    wait(stim.gen_done.triggered);
    $finish();
  endtask
  
  task execute();
    setup();
    run_test();
    cleanup();
  endtask
endclass

/////////////////////////////////////////////////////

module tb_flipflop;
  flipflop_if vif_if();

  flipflop dut(vif_if);
  
  initial begin
    vif_if.clk_sig <= 0;
  end
  
  always #10 vif_if.clk_sig <= ~vif_if.clk_sig;
  
  verification_env env;

  initial begin
    env = new(vif_if);
    env.stim.num_stimuli = 30;
    env.execute();
  end
  
  initial begin
    $dumpfile("simulation.vcd");
    $dumpvars;
  end
endmodule
