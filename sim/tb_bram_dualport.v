`timescale 1ns/1ps

module tb_bram_dualport;

reg clk;
reg en_a;
reg [3:0] wstrb_a;
reg [3:0] addr_a;
reg [31:0] wdata_a;
wire [31:0] rdata_a;
reg en_b;
reg [3:0] addr_b;
wire [31:0] rdata_b;

bram_dualport #(
    .ADDR_WIDTH(4),
    .USE_INIT_FILE(0)
) dut (
    .clk_a(clk),
    .en_a(en_a),
    .addr_a(addr_a),
    .wdata_a(wdata_a),
    .wstrb_a(wstrb_a),
    .rdata_a(rdata_a),
    .clk_b(clk),
    .en_b(en_b),
    .addr_b(addr_b),
    .rdata_b(rdata_b)
);

always #5 clk = ~clk;

initial begin
    clk = 1'b0;
    en_a = 1'b0;
    wstrb_a = 4'b0000;
    addr_a = 4'h0;
    wdata_a = 32'h0000_0000;
    en_b = 1'b0;
    addr_b = 4'h0;

    @(negedge clk);
    en_a = 1'b1;
    addr_a = 4'h3;
    wdata_a = 32'h1122_3344;
    wstrb_a = 4'b1111;
    @(posedge clk);
    @(negedge clk);
    wstrb_a = 4'b0000;
    en_b = 1'b1;
    addr_b = 4'h3;
    @(posedge clk);
    @(negedge clk);
    if (rdata_b !== 32'h1122_3344) begin
        $display("FAIL: 端口 B 没有读到端口 A 写入的数据");
        $finish;
    end

    @(negedge clk);
    @(posedge clk);
    @(negedge clk);
    if (rdata_a !== 32'h1122_3344) begin
        $display("FAIL: 端口 A 普通读回错误");
        $finish;
    end

    @(negedge clk);
    wdata_a = 32'hAABB_CCDD;
    wstrb_a = 4'b0011;
    en_a = 1'b1;
    en_b = 1'b1;
    addr_b = 4'h3;
    @(posedge clk);
    @(negedge clk);
    wstrb_a = 4'b0000;
    @(posedge clk);
    @(negedge clk);
    if (rdata_b !== 32'h1122_CCDD) begin
        $display("FAIL: 字节写掩码后，端口 B 看到的数据不正确");
        $finish;
    end

    $display("PASS: bram_dualport 读写与双端口行为符合预期");
    $finish;
end

endmodule
