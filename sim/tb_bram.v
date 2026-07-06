// bram 的最小读写仿真。
// 覆盖两个关键行为：整字写入，以及 wstrb 控制的字节局部写入。
`timescale 1ns/1ps

module tb_bram;

reg clk;
reg en;
reg [1:0] addr;
reg [31:0] wdata;
reg [3:0] wstrb;

wire [31:0] rdata;

bram #(
    .ADDR_WIDTH(2),
    .USE_INIT_FILE(0)
) dut (
    .clk(clk),
    .en(en),
    .addr(addr),
    .wdata(wdata),
    .wstrb(wstrb),
    .rdata(rdata)
);

always #5 clk = ~clk;

initial begin
    clk = 1'b0;
    en = 1'b0;
    addr = 2'b00;
    wdata = 32'h0000_0000;
    wstrb = 4'b0000;

    $dumpfile("sim/build/tb_bram.vcd");
    $dumpvars(0, tb_bram);

    @(negedge clk);
    en = 1'b1;
    addr = 2'b01;
    wdata = 32'h1122_3344;
    // 4'b1111 表示 4 个 byte lane 全部写入。
    wstrb = 4'b1111;
    @(posedge clk);

    @(negedge clk);
    wstrb = 4'b0000;
    @(posedge clk);
    #1;
    if (rdata !== 32'h1122_3344) begin
        $display("FAIL: BRAM 全字写后读回不正确");
        $finish;
    end

    @(negedge clk);
    wdata = 32'hAA00_00BB;
    // 只写最高字节和最低字节，中间两个字节应保持原值 22_33。
    wstrb = 4'b1001;
    @(posedge clk);

    @(negedge clk);
    wstrb = 4'b0000;
    @(posedge clk);
    #1;
    if (rdata !== 32'hAA22_33BB) begin
        $display("FAIL: BRAM 字节写使能行为不正确");
        $finish;
    end

    $display("PASS: bram 读写与字节写使能符合预期");
    $finish;
end

endmodule
