// machine_timer 的计数、比较、level IRQ 与 write-wins 定向测试。
`timescale 1ns/1ps

module tb_machine_timer;

reg clk;
reg reset;
reg mtime_lo_we;
reg mtime_hi_we;
reg mtimecmp_lo_we;
reg mtimecmp_hi_we;
reg [31:0] wdata;

wire [31:0] mtime_lo_rdata;
wire [31:0] mtime_hi_rdata;
wire [31:0] mtimecmp_lo_rdata;
wire [31:0] mtimecmp_hi_rdata;
wire irq;

reg [63:0] compare_value;
reg [63:0] future_value;
integer wait_cycles;

machine_timer dut (
    .clk(clk),
    .reset(reset),
    .mtime_lo_we(mtime_lo_we),
    .mtime_hi_we(mtime_hi_we),
    .mtimecmp_lo_we(mtimecmp_lo_we),
    .mtimecmp_hi_we(mtimecmp_hi_we),
    .wdata(wdata),
    .mtime_lo_rdata(mtime_lo_rdata),
    .mtime_hi_rdata(mtime_hi_rdata),
    .mtimecmp_lo_rdata(mtimecmp_lo_rdata),
    .mtimecmp_hi_rdata(mtimecmp_hi_rdata),
    .irq(irq)
);

always #5 clk = ~clk;

task write_register;
    input [3:0] select;
    input [31:0] value;
    begin
        @(negedge clk);
        wdata = value;
        {mtimecmp_hi_we, mtimecmp_lo_we, mtime_hi_we, mtime_lo_we} = select;
        @(negedge clk);
        {mtimecmp_hi_we, mtimecmp_lo_we, mtime_hi_we, mtime_lo_we} = 4'b0000;
    end
endtask

initial begin
    clk = 1'b0;
    reset = 1'b1;
    mtime_lo_we = 1'b0;
    mtime_hi_we = 1'b0;
    mtimecmp_lo_we = 1'b0;
    mtimecmp_hi_we = 1'b0;
    wdata = 32'd0;

    repeat (3) @(posedge clk);
    #1;
    if ({mtime_hi_rdata, mtime_lo_rdata} !== 64'd0 ||
        {mtimecmp_hi_rdata, mtimecmp_lo_rdata} !== 64'hffff_ffff_ffff_ffff || irq) begin
        $display("FAIL: reset 后 machine timer 状态错误");
        $finish;
    end
    reset = 1'b0;

    // 写 mtime 的半字必须覆盖同一拍的自增结果。
    write_register(4'b0001, 32'd100);
    if (mtime_lo_rdata !== 32'd100) begin
        $display("FAIL: mtime low 未采用 write-wins，实际值=%0d", mtime_lo_rdata);
        $finish;
    end
    write_register(4'b0010, 32'd1);
    if (mtime_hi_rdata !== 32'd1) begin
        $display("FAIL: mtime high 写入失败");
        $finish;
    end

    compare_value = {mtime_hi_rdata, mtime_lo_rdata} + 64'd8;
    write_register(4'b1000, compare_value[63:32]);
    write_register(4'b0100, compare_value[31:0]);
    if (irq) begin
        $display("FAIL: compare 尚未到达时 timer IRQ 意外拉高");
        $finish;
    end

    wait_cycles = 0;
    while (!irq && wait_cycles < 12) begin
        @(posedge clk);
        #1;
        wait_cycles = wait_cycles + 1;
    end
    if (!irq || {mtime_hi_rdata, mtime_lo_rdata} < compare_value) begin
        $display("FAIL: mtime 到达 compare 后 timer IRQ 未拉高");
        $finish;
    end
    repeat (2) @(posedge clk);
    #1;
    if (!irq) begin
        $display("FAIL: timer IRQ 未保持 level high");
        $finish;
    end

    future_value = {mtime_hi_rdata, mtime_lo_rdata} + 64'd8;
    write_register(4'b1000, future_value[63:32]);
    write_register(4'b0100, future_value[31:0]);
    if (irq) begin
        $display("FAIL: compare 更新到未来后 timer IRQ 未释放");
        $finish;
    end

    $display("PASS: machine timer 计数、比较与 level IRQ 语义通过");
    $finish;
end

endmodule
