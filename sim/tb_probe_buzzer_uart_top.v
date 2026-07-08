// probe_buzzer_uart_top 的调试版仿真。
// 这里不解码真正串口波形，而是在 reporter -> uart_tx 的 valid/ready 握手点检查 token 顺序；
// 同时确认蜂鸣器输出在一段时间内确实发生了翻转。
`timescale 1ns/1ps

module tb_probe_buzzer_uart_top;

reg clk;
reg reset;
reg uart_rxd;

wire uart_txd;
wire [3:0] led;
wire mf;
wire clr;
wire spk;
wire [7:0] s;

reg [7:0] expected [0:30];
integer accepted_count;
integer spk_edges;
reg spk_d;

probe_buzzer_uart_top #(
    .CLK_FREQ(1000000),
    .UART_BAUD(1000000),
    .BEAT_TICKS(5000),
    .MF_DEFAULT(1'b0),
    .CLR_DEFAULT(1'b1),
    .S_DEFAULT(8'ha5)
) dut (
    .clk(clk),
    .reset(reset),
    .uart_rxd(uart_rxd),
    .uart_txd(uart_txd),
    .led(led),
    .mf(mf),
    .clr(clr),
    .spk(spk),
    .s(s)
);

always #5 clk = ~clk;

always @(posedge clk) begin
    spk_d <= spk;
    if (reset && (spk_d != spk)) begin
        spk_edges <= spk_edges + 1;
    end

    if (!reset) begin
        accepted_count <= 0;
        spk_edges <= 0;
        spk_d <= 1'b0;
    end else if (dut.reporter_valid && dut.uart_ready) begin
        if (dut.reporter_data !== expected[accepted_count]) begin
            $display("FAIL: 第 %0d 个 UART 调试字节错误，期望 0x%02x，实际 0x%02x",
                accepted_count, expected[accepted_count], dut.reporter_data);
            $finish;
        end
        accepted_count <= accepted_count + 1;
        if (accepted_count == 30) begin
            if (spk_edges == 0) begin
                $display("FAIL: UART 消息已发送，但蜂鸣器输出没有发生翻转");
                $finish;
            end
            if (mf !== 1'b0 || clr !== 1'b1 || s !== 8'ha5) begin
                $display("FAIL: 控制脚默认值不正确 mf=%b clr=%b s=%02x", mf, clr, s);
                $finish;
            end
            $display("PASS: probe_buzzer_uart_top 蜂鸣器和 UART 调试 token 正常");
            $finish;
        end
    end
end

initial begin
    clk = 1'b0;
    reset = 1'b0;
    uart_rxd = 1'b1;
    accepted_count = 0;
    spk_edges = 0;
    spk_d = 1'b0;

    expected[0] = "3";
    expected[1] = 8'h0d;
    expected[2] = 8'h0a;
    expected[3] = "2";
    expected[4] = "_";
    expected[5] = 8'h0d;
    expected[6] = 8'h0a;
    expected[7] = "1";
    expected[8] = 8'h0d;
    expected[9] = 8'h0a;
    expected[10] = "2";
    expected[11] = "_";
    expected[12] = 8'h0d;
    expected[13] = 8'h0a;
    expected[14] = "3";
    expected[15] = "_";
    expected[16] = 8'h0d;
    expected[17] = 8'h0a;
    expected[18] = "4";
    expected[19] = "_";
    expected[20] = "_";
    expected[21] = 8'h0d;
    expected[22] = 8'h0a;
    expected[23] = "3";
    expected[24] = "_";
    expected[25] = 8'h0d;
    expected[26] = 8'h0a;
    expected[27] = "2";
    expected[28] = "-";
    expected[29] = 8'h0d;
    expected[30] = 8'h0a;

    $dumpfile("sim/build/tb_probe_buzzer_uart_top.vcd");
    $dumpvars(0, tb_probe_buzzer_uart_top);

    repeat (2) @(posedge clk);
    reset = 1'b1;

    repeat (120000) @(posedge clk);
    $display("FAIL: probe_buzzer_uart_top 在超时前未发完首轮调试 token");
    $finish;
end

endmodule
