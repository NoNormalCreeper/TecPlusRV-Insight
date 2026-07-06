`timescale 1ns/1ps

module tb_probe_uart_top;

reg clk;
reg reset;
reg uart_rxd;
reg [7:0] expected [0:16];
integer accepted_count;

wire uart_txd;

probe_uart_top dut (
    .clk(clk),
    .reset(reset),
    .uart_rxd(uart_rxd),
    .uart_txd(uart_txd)
);

always #5 clk = ~clk;

always @(posedge clk) begin
    if (!reset) begin
        accepted_count <= 0;
    end else if (dut.tx_valid && dut.tx_ready) begin
        if (dut.tx_data !== expected[accepted_count]) begin
            $display("FAIL: 第 %0d 个发送字节错误，期望 0x%02x，实际 0x%02x",
                     accepted_count, expected[accepted_count], dut.tx_data);
            $finish;
        end

        accepted_count <= accepted_count + 1;

        if (accepted_count == 16) begin
            $display("PASS: probe_uart_top 发送完整消息顺序正确");
            $finish;
        end
    end
end

initial begin
    clk = 1'b0;
    reset = 1'b0;
    uart_rxd = 1'b1;
    accepted_count = 0;

    expected[0] = "H";
    expected[1] = "e";
    expected[2] = "l";
    expected[3] = "l";
    expected[4] = "o";
    expected[5] = " ";
    expected[6] = "T";
    expected[7] = "e";
    expected[8] = "c";
    expected[9] = "P";
    expected[10] = "l";
    expected[11] = "u";
    expected[12] = "s";
    expected[13] = "R";
    expected[14] = "V";
    expected[15] = 8'h0d;
    expected[16] = 8'h0a;

    $dumpfile("sim/build/tb_probe_uart_top.vcd");
    $dumpvars(0, tb_probe_uart_top);

    repeat (2) @(posedge clk);
    reset = 1'b1;

    @(negedge clk);
    dut.gap_count = 26'd49_999_999;
    @(posedge clk);
    #1;
    if (dut.send_active !== 1'b1) begin
        $display("FAIL: gap 结束后应开始发送消息");
        $finish;
    end

    repeat (1200000) @(posedge clk);
    $display("FAIL: probe_uart_top 在超时前未完成完整消息发送");
    $finish;
end

endmodule
