// traffic_light_gpio reset, full-word write, and byte-strobe behavior.
`timescale 1ns/1ps

module tb_traffic_light_gpio;

reg clk;
reg reset;
reg write_en;
reg [31:0] write_data;
reg [3:0] write_strobe;
wire [11:0] tl;

traffic_light_gpio dut (
    .clk(clk),
    .reset(reset),
    .write_en(write_en),
    .write_data(write_data),
    .write_strobe(write_strobe),
    .tl(tl)
);

always #5 clk = ~clk;

task write_pattern;
    input [31:0] value;
    input [3:0] strobe;
    begin
        @(negedge clk);
        write_data = value;
        write_strobe = strobe;
        write_en = 1'b1;
        @(negedge clk);
        write_en = 1'b0;
        write_strobe = 4'b0000;
    end
endtask

initial begin
    clk = 1'b0;
    reset = 1'b1;
    write_en = 1'b0;
    write_data = 32'h0000_0000;
    write_strobe = 4'b0000;

    $dumpfile("sim/build/tb_traffic_light_gpio.vcd");
    $dumpvars(0, tb_traffic_light_gpio);

    repeat (3) @(posedge clk);
    if (tl !== 12'h000) begin
        $display("FAIL: reset value expected 000, got %03x", tl);
        $finish;
    end

    reset = 1'b0;
    write_pattern(32'h0000_0a55, 4'b1111);
    if (tl !== 12'ha55) begin
        $display("FAIL: full write expected a55, got %03x", tl);
        $finish;
    end

    write_pattern(32'h0000_003c, 4'b0001);
    if (tl !== 12'ha3c) begin
        $display("FAIL: low-byte write expected a3c, got %03x", tl);
        $finish;
    end

    write_pattern(32'h0000_0500, 4'b0010);
    if (tl !== 12'h53c) begin
        $display("FAIL: upper-nibble write expected 53c, got %03x", tl);
        $finish;
    end

    write_pattern(32'hffff_ffff, 4'b1100);
    if (tl !== 12'h53c) begin
        $display("FAIL: unrelated byte strobes changed TL, got %03x", tl);
        $finish;
    end

    reset = 1'b1;
    @(posedge clk);
    #1;
    if (tl !== 12'h000) begin
        $display("FAIL: warm reset expected 000, got %03x", tl);
        $finish;
    end

    $display("PASS: traffic_light_gpio register and byte strobes");
    $finish;
end

endmodule
