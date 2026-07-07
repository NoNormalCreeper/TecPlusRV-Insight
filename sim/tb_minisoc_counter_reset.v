`timescale 1ns/1ps

module tb_minisoc_counter_reset #(
    parameter integer CPU_IMPL = 0,
    parameter integer RUN_CYCLES_BEFORE_RESET = 20,
    parameter integer RESET_HOLD_CYCLES = 2
);

reg clk;
reg reset;
reg [3:0] key;

wire [3:0] led;
wire uart_txd;
integer cycle_before_reset;
integer instret_before_reset;

tecplus_minisoc_top #(
    .CLK_FREQ(1000000),
    .UART_BAUD(100000),
    .CPU_IMPL(CPU_IMPL),
    .BRAM_ADDR_WIDTH(14),
    .BRAM_INIT_FILE("firmware/build/firmware.mem")
) dut (
    .clk(clk),
    .reset(reset),
    .key(key),
    .led(led),
    .uart_rxd(1'b1),
    .uart_txd(uart_txd)
);

always #5 clk = ~clk;

initial begin
    clk = 1'b0;
    reset = 1'b0;
    key = 4'b1111;

    repeat (5) @(posedge clk);
    reset = 1'b1;

    repeat (RUN_CYCLES_BEFORE_RESET) @(posedge clk);
    cycle_before_reset = dut.cycle_rdata;
    instret_before_reset = dut.instret_rdata;

    if (cycle_before_reset == 0) begin
        $display("FAIL: reset 前 cycle 计数没有前进，测试前提不成立");
        $finish;
    end

    reset = 1'b0;
    repeat (RESET_HOLD_CYCLES) @(posedge clk);

    if (dut.cycle_rdata !== 32'h0000_0000) begin
        $display("FAIL: warm reset 后 cycle 没有清零，before=%0d after=%0d", cycle_before_reset, dut.cycle_rdata);
        $finish;
    end

    if (instret_before_reset != 0 && dut.instret_rdata !== 32'h0000_0000) begin
        $display("FAIL: warm reset 后 instret 没有清零，before=%0d after=%0d", instret_before_reset, dut.instret_rdata);
        $finish;
    end

    $display("PASS: warm reset 会清零 core-backed counters");
    $finish;
end

endmodule
