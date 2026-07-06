`timescale 1ns/1ps

module tb_mmio_test_exit;

reg clk;
reg reset;
reg write_en;
reg [31:0] write_data;

wire exited;
wire [31:0] exit_code;

mmio_test_exit dut (
    .clk(clk),
    .reset(reset),
    .write_en(write_en),
    .write_data(write_data),
    .exited(exited),
    .exit_code(exit_code)
);

always #5 clk = ~clk;

initial begin
    clk = 1'b0;
    reset = 1'b1;
    write_en = 1'b0;
    write_data = 32'h0000_0000;

    $dumpfile("sim/build/tb_mmio_test_exit.vcd");
    $dumpvars(0, tb_mmio_test_exit);

    repeat (2) @(posedge clk);
    #1;
    if (exited !== 1'b0 || exit_code !== 32'h0000_0000) begin
        $display("FAIL: reset 后 test_exit 状态应清零");
        $finish;
    end

    reset = 1'b0;
    @(negedge clk);
    write_en = 1'b1;
    write_data = 32'h0000_0007;
    @(posedge clk);
    #1;
    if (exited !== 1'b1 || exit_code !== 32'h0000_0007) begin
        $display("FAIL: 写 test_exit 后状态不正确");
        $finish;
    end

    @(negedge clk);
    write_en = 1'b0;
    write_data = 32'hDEAD_BEEF;
    @(posedge clk);
    #1;
    if (exit_code !== 32'h0000_0007) begin
        $display("FAIL: write_en=0 时 exit_code 不应变化");
        $finish;
    end

    $display("PASS: mmio_test_exit 基本行为符合预期");
    $finish;
end

endmodule
