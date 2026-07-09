// buzzer_pwm register, divider, enable, and zero-period behavior.
`timescale 1ns/1ps

module tb_buzzer_pwm;

reg clk;
reg reset;
reg ctrl_write_en;
reg period_write_en;
reg [31:0] write_data;
reg [3:0] write_strobe;

wire enabled;
wire [31:0] half_period;
wire spk;

buzzer_pwm dut (
    .clk(clk),
    .reset(reset),
    .ctrl_write_en(ctrl_write_en),
    .period_write_en(period_write_en),
    .write_data(write_data),
    .write_strobe(write_strobe),
    .enabled(enabled),
    .half_period(half_period),
    .spk(spk)
);

always #5 clk = ~clk;

task write_period;
    input [31:0] value;
    input [3:0] strobe;
    begin
        @(negedge clk);
        write_data = value;
        write_strobe = strobe;
        period_write_en = 1'b1;
        @(negedge clk);
        period_write_en = 1'b0;
        write_strobe = 4'b0000;
    end
endtask

task write_ctrl;
    input value;
    begin
        @(negedge clk);
        write_data = {31'd0, value};
        write_strobe = 4'b0001;
        ctrl_write_en = 1'b1;
        @(negedge clk);
        ctrl_write_en = 1'b0;
        write_strobe = 4'b0000;
    end
endtask

initial begin
    clk = 1'b0;
    reset = 1'b1;
    ctrl_write_en = 1'b0;
    period_write_en = 1'b0;
    write_data = 32'd0;
    write_strobe = 4'b0000;

    $dumpfile("sim/build/tb_buzzer_pwm.vcd");
    $dumpvars(0, tb_buzzer_pwm);

    repeat (3) @(posedge clk);
    if (enabled || half_period !== 0 || spk) begin
        $display("FAIL: reset should disable buzzer and clear registers");
        $finish;
    end
    reset = 1'b0;

    write_period(32'd3, 4'b1111);
    if (half_period !== 32'd3 || spk) begin
        $display("FAIL: period write expected 3 and low SPK");
        $finish;
    end

    write_ctrl(1'b1);
    if (!enabled || spk) begin
        $display("FAIL: enable write did not start from low SPK");
        $finish;
    end

    repeat (3) @(posedge clk);
    #1;
    if (!spk) begin
        $display("FAIL: SPK did not toggle high after one half-period");
        $finish;
    end

    repeat (3) @(posedge clk);
    #1;
    if (spk) begin
        $display("FAIL: SPK did not toggle low after two half-periods");
        $finish;
    end

    write_ctrl(1'b0);
    if (enabled || spk) begin
        $display("FAIL: stop should disable buzzer and drive SPK low");
        $finish;
    end

    write_period(32'd0, 4'b1111);
    write_ctrl(1'b1);
    repeat (10) @(posedge clk);
    #1;
    if (!enabled || spk) begin
        $display("FAIL: zero period should keep SPK low");
        $finish;
    end

    $display("PASS: buzzer_pwm divider and control behavior");
    $finish;
end

endmodule
