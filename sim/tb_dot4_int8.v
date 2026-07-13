// signed INT8 DOT4 协处理器单元测试。
// 检查 lane 顺序、有符号边界、固定响应节奏和请求去重。
`timescale 1ns/1ps

module tb_dot4_int8;

reg clk;
reg reset;
reg req;
reg [31:0] rs1;
reg [31:0] rs2;
wire ack;
wire [31:0] result;

dot4_int8 dut (
    .clk(clk),
    .reset(reset),
    .req(req),
    .rs1(rs1),
    .rs2(rs2),
    .ack(ack),
    .result(result)
);

always #5 clk = ~clk;

task run_case;
    input [31:0] case_rs1;
    input [31:0] case_rs2;
    input [31:0] expected;
    begin
        @(negedge clk);
        rs1 = case_rs1;
        rs2 = case_rs2;
        req = 1'b1;

        @(posedge clk);
        #1;
        if (ack !== 1'b0) begin
            $display("FAIL: 接收请求当拍不应 ack");
            $finish;
        end

        @(posedge clk);
        #1;
        if (ack !== 1'b1 || result !== expected) begin
            $display("FAIL: DOT4 结果错误 rs1=%08x rs2=%08x got=%08x expected=%08x ack=%b",
                case_rs1, case_rs2, result, expected, ack);
            $finish;
        end

        // CPU 在看到 ack 后推进到下一条指令，普通指令会在下一个采样沿前撤销 req。
        @(negedge clk);
        req = 1'b0;
        @(posedge clk);
        #1;
        if (ack !== 1'b0) begin
            $display("FAIL: 同一 req 被重复 ack");
            $finish;
        end
    end
endtask

task run_back_to_back;
    begin
        @(negedge clk);
        rs1 = 32'h0101_0101;
        rs2 = 32'h0101_0101;
        req = 1'b1;
        @(posedge clk);
        @(posedge clk);
        #1;
        if (ack !== 1'b1 || result !== 32'd4) begin
            $display("FAIL: 背靠背测试的第一条 DOT4 未响应");
            $finish;
        end

        // ACK 代表上一 transaction 完成；下一条 DOT4 可以让 req 连续为高。
        @(negedge clk);
        rs1 = 32'h0202_0202;
        rs2 = 32'h0303_0303;
        @(posedge clk);
        #1;
        if (ack !== 1'b0) begin
            $display("FAIL: 第二条 DOT4 接收当拍错误 ack");
            $finish;
        end
        @(posedge clk);
        #1;
        if (ack !== 1'b1 || result !== 32'd24) begin
            $display("FAIL: 连续为高的 req 未被识别为下一条 DOT4");
            $finish;
        end

        @(negedge clk);
        req = 1'b0;
        @(posedge clk);
        #1;
    end
endtask

initial begin
    clk = 1'b0;
    reset = 1'b1;
    req = 1'b0;
    rs1 = 32'h0000_0000;
    rs2 = 32'h0000_0000;

    repeat (2) @(posedge clk);
    reset = 1'b0;

    run_case(32'h0000_0000, 32'h0000_0000, 32'd0);
    run_case(32'h0403_0201, 32'h0807_0605, 32'd70);
    run_case(32'h80ff_017f, 32'h7f02_ff80, -32'sd32515);
    run_case(32'h8080_8080, 32'h8080_8080, 32'd65536);
    run_back_to_back();

    // pending 请求被 reset 时必须取消，不能在 reset 后冒出旧响应。
    @(negedge clk);
    rs1 = 32'h0101_0101;
    rs2 = 32'h0101_0101;
    req = 1'b1;
    @(posedge clk);
    #1;
    reset = 1'b1;
    @(posedge clk);
    #1;
    if (ack !== 1'b0) begin
        $display("FAIL: reset 未清除 pending 响应");
        $finish;
    end
    req = 1'b0;
    reset = 1'b0;
    repeat (2) @(posedge clk);
    if (ack !== 1'b0) begin
        $display("FAIL: reset 后出现伪 ack");
        $finish;
    end

    $display("PASS: signed INT8 DOT4 计算与握手语义正确");
    $finish;
end

initial begin
    repeat (100) @(posedge clk);
    $display("TIMEOUT: DOT4 单元测试未完成");
    $finish;
end

endmodule
