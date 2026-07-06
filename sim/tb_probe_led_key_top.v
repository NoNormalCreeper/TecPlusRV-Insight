// probe_led_key_top 的板级探针仿真。
// 真实板上 tick 很慢；testbench 会直接改 dut.tick_count 来跳过等待时间。
`timescale 1ns/1ps

module tb_probe_led_key_top;

reg clk;
reg reset;
reg [3:0] key;

wire [3:0] led;

probe_led_key_top dut (
    .clk(clk),
    .reset(reset),
    .key(key),
    .led(led)
);

always #5 clk = ~clk;

task press_key;
    input integer index;
    begin
        // KEY 为低有效，这里制造一个短按：拉低一拍再释放。
        @(negedge clk);
        key[index] = 1'b0;
        @(negedge clk);
        key[index] = 1'b1;
    end
endtask

initial begin
    clk = 1'b0;
    reset = 1'b0;
    key = 4'b1111;

    $dumpfile("sim/build/tb_probe_led_key_top.vcd");
    $dumpvars(0, tb_probe_led_key_top);

    repeat (2) @(posedge clk);
    if (led !== 4'b0000) begin
        $display("FAIL: reset 期间 LED 应全灭");
        $finish;
    end

    reset = 1'b1;

    @(negedge clk);
    // 直接写 DUT 内部计数器是仿真加速手段，不是综合路径。
    dut.tick_count = 26'd24_999_999;
    @(posedge clk);
    #1;
    if (led !== 4'b0001) begin
        $display("FAIL: 释放 reset 后第一次步进应点亮 led[0]");
        $finish;
    end

    @(negedge clk);
    dut.tick_count = 26'd24_999_999;
    @(posedge clk);
    #1;
    if (led !== 4'b0010) begin
        $display("FAIL: 跑马灯第二步应点亮 led[1]");
        $finish;
    end

    press_key(0);
    @(posedge clk);
    #1;
    if (dut.speed_fast !== 1'b1) begin
        $display("FAIL: KEY1 应切换到快速模式");
        $finish;
    end

    press_key(1);
    @(posedge clk);
    #1;
    if (dut.fixed_mode !== 1'b1) begin
        $display("FAIL: KEY2 应切换到固定显示模式");
        $finish;
    end
    if (led !== 4'b1010) begin
        $display("FAIL: 固定显示模式应输出 1010");
        $finish;
    end

    $display("PASS: probe_led_key_top 基本行为符合预期");
    $finish;
end

endmodule
