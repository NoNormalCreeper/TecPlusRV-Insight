// probe_bigboard_tl_top 的 thin-probe 仿真。
// 只验证 tl 单 1 轮转和 LED 心跳存在，不验证真实交通灯业务时序。
`timescale 1ns/1ps

module tb_bigboard_tl;

reg clk;
reg reset;

wire [3:0]  led;
wire [11:0] tl;

probe_bigboard_tl_top #(
    .STEP_TICKS(4)
) dut (
    .clk(clk),
    .reset(reset),
    .led(led),
    .tl(tl)
);

always #5 clk = ~clk;

initial begin
    clk = 1'b0;
    reset = 1'b0;

    $dumpfile("sim/build/tb_bigboard_tl.vcd");
    $dumpvars(0, tb_bigboard_tl);

    #25;
    reset = 1'b1;

    @(posedge clk);
    if (tl !== 12'b0000_0000_0001) begin
        $display("FAIL: 初始图样不正确");
        $finish;
    end

    repeat (4) @(posedge clk);
    if (tl !== 12'b0000_0000_0010) begin
        $display("FAIL: 第一次移位图样不正确");
        $finish;
    end

    repeat (4) @(posedge clk);
    if (tl !== 12'b0000_0000_0100) begin
        $display("FAIL: 第二次移位图样不正确");
        $finish;
    end

    if (led == 4'b0000) begin
        $display("FAIL: LED 心跳镜像不应全灭");
        $finish;
    end

    $display("PASS: probe_bigboard_tl_top 图样轮转正常");
    $finish;
end

endmodule
