`timescale 1ns/1ps

module tb_probe_uart_top;

reg clk;
reg reset;
reg uart_rxd;

wire uart_txd;

probe_uart_top dut (
    .clk(clk),
    .reset(reset),
    .uart_rxd(uart_rxd),
    .uart_txd(uart_txd)
);

always #5 clk = ~clk;

initial begin
    clk = 1'b0;
    reset = 1'b1;
    uart_rxd = 1'b1;

    $dumpfile("sim/build/tb_probe_uart_top.vcd");
    $dumpvars(0, tb_probe_uart_top);

    repeat (2) @(posedge clk);
    reset = 1'b0;

    @(negedge clk);
    dut.gap_count = 26'd49_999_999;
    @(posedge clk);
    #1;
    if (dut.send_active !== 1'b1) begin
        $display("FAIL: gap 结束后应开始发送消息");
        $finish;
    end

    @(posedge clk);
    #1;
    if (dut.tx_valid !== 1'b1 || dut.tx_data !== "H") begin
        $display("FAIL: 首字节应为 H");
        $finish;
    end

    @(posedge clk);
    #1;
    if (dut.tx_valid !== 1'b1 || dut.tx_data !== "e") begin
        $display("FAIL: 次字节应为 e");
        $finish;
    end

    $display("PASS: probe_uart_top 周期发送路径符合预期");
    $finish;
end

endmodule
