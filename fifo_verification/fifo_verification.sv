module FIFO(
    input clk, rst, wr, rd,
    input [7:0] din,
    output reg [7:0] dout,
    output empty, full
);

    reg [3:0] write_ptr = 0, read_ptr = 0;  // Renamed wptr and rptr
    reg [4:0] element_count = 0;           // Renamed cnt
    reg [7:0] memory [15:0];               // Renamed mem

    always @(posedge clk) begin
        if (rst == 1'b1) begin
            write_ptr <= 0;
            read_ptr <= 0;
            element_count <= 0;
        end
        else if (wr && !full) begin
            memory[write_ptr] <= din;
            write_ptr <= write_ptr + 1;
            element_count <= element_count + 1;
        end
        else if (rd && !empty) begin
            dout <= memory[read_ptr];
            read_ptr <= read_ptr + 1;
            element_count <= element_count - 1;
        end
    end

    assign empty = (element_count == 0) ? 1'b1 : 1'b0;
    assign full = (element_count == 16) ? 1'b1 : 1'b0;

endmodule

//////////////////////////////////////

interface fifo_if;

    logic clk, rd, wr;         // Renamed clock to clk
    logic full, empty;
    logic [7:0] din;           // Renamed data_in to din
    logic [7:0] dout;          // Renamed data_out to dout
    logic rst;

endinterface
