// probe_bigboard_tl_top 的 thin-probe 仿真。
// 只验证 tl 诊断图样轮转，不验证真实交通灯业务时序。
`timescale 1ns/1ps

module tb_bigboard_tl;

reg clk;
reg reset;

wire [3:0]  led;
wire [11:0] tl;
integer i;

probe_bigboard_tl_top #(
    .STEP_TICKS(4)
) dut (
    .clk(clk),
    .reset(reset),
    .led(led),
    .tl(tl)
);

always #5 clk = ~clk;

task expect_outputs;
    input [11:0] expected_tl;
    input [3:0] expected_led;
    input [127:0] label;
    begin
        #1;
        if (tl !== expected_tl) begin
            $display("FAIL: %0s tl 期望 %03h，实际 %03h", label, expected_tl, tl);
            $finish;
        end
        if (led !== expected_led) begin
            $display("FAIL: %0s led 期望 %b，实际 %b", label, expected_led, led);
            $finish;
        end
    end
endtask

task step_once;
    begin
        repeat (4) @(posedge clk);
        #1;
    end
endtask

initial begin
    clk = 1'b0;
    reset = 1'b0;

    $dumpfile("sim/build/tb_bigboard_tl.vcd");
    $dumpvars(0, tb_bigboard_tl);

    #25;
    reset = 1'b1;

    @(posedge clk);
    expect_outputs(12'h000, 4'b0001, "all-low phase");

    step_once();
    expect_outputs(12'hfff, 4'b0010, "all-high phase");

    step_once();
    expect_outputs(12'h001, 4'b0100, "walk-one bit 0");

    for (i = 1; i < 12; i = i + 1) begin
        step_once();
        expect_outputs(12'h001 << i, 4'b0100, "walk-one phase");
    end

    step_once();
    expect_outputs(12'hffe, 4'b1000, "walk-zero bit 0");

    step_once();
    expect_outputs(12'hffd, 4'b1000, "walk-zero bit 1");

    $display("PASS: probe_bigboard_tl_top 诊断图样轮转正常");
    $finish;
end

endmodule
