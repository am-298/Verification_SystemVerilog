module flipflop (flipflop_if vif_if);

  always @(posedge vif_if.clk_sig)
    begin
      if (vif_if.rst_sig == 1'b1)
        vif_if.out_sig <= 1'b0;
      else
        vif_if.out_sig <= vif_if.in_sig;
    end
  
endmodule

interface flipflop_if;
  logic clk_sig;
  logic rst_sig;
  logic in_sig;
  logic out_sig;
endinterface