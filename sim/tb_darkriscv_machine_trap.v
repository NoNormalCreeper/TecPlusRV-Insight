// DarkRISCV machine trap core-level 定向测试。
// 旧 RTL 只有 MIP[11] && JREQ 时才跳转，因此 IRQ 必须在连续 addi 区间内失败。
`timescale 1ns/1ps

module tb_darkriscv_machine_trap #(
    parameter FIRMWARE_MEM_FILE = "sim/build/darkriscv_machine_trap.mem"
);

reg clk;
reg reset;
reg irq;
reg [31:0] imem [0:16383];
reg [31:0] store_value [0:2];
reg [31:0] last_store_addr;
integer store_count;
integer i;
reg entered_mtvec;

wire idreq;
wire [31:0] iaddr;
wire ddreq;
wire [31:0] daddr;
wire [2:0] dlen;
wire [3:0] dbe;
wire drw;
wire drd;
wire dwr;
wire [31:0] datao;
wire [31:0] perf_cycle;
wire [31:0] perf_instret;
wire [3:0] debug;

wire [31:0] idata = imem[iaddr[15:2]];

darkriscv dut (
    .CLK(clk),
    .RES(reset),
    .IRQ(irq),
    .IDREQ(idreq),
    .IADDR(iaddr),
    .IDATA(idata),
    .IDACK(1'b1),
    .IBERR(1'b0),
    .DDREQ(ddreq),
    .DADDR(daddr),
    .DLEN(dlen),
    .DBE(dbe),
    .DRW(drw),
    .DRD(drd),
    .DWR(dwr),
    .DATAO(datao),
    .DATAI(32'h0000_0000),
    .DDACK(1'b1),
    .DBERR(1'b0),
    .PERF_CYCLE(perf_cycle),
    .PERF_INSTRET(perf_instret),
    .DEBUG(debug)
);

always #5 clk = ~clk;

always @(posedge clk) begin
    if (!reset && iaddr == 32'h0000_0200) begin
        entered_mtvec <= 1'b1;
    end

    if (ddreq && dwr && (store_count == 0 || daddr != last_store_addr)) begin
        if (store_count < 3) begin
            store_value[store_count] <= datao;
            store_count <= store_count + 1;
        end
        last_store_addr <= daddr;
    end
end

initial begin
    clk = 1'b0;
    reset = 1'b1;
    irq = 1'b0;
    entered_mtvec = 1'b0;
    store_count = 0;
    last_store_addr = 32'hffff_ffff;
    for (i = 0; i < 3; i = i + 1) begin
        store_value[i] = 32'h0000_0000;
    end
    $readmemh(FIRMWARE_MEM_FILE, imem);

    repeat (4) @(posedge clk);
    reset = 1'b0;

    // s0 的 signature 出现后仍处于 64 条连续 addi 的前段。
    wait (dut.REGS[8] == 32'h1234_5678);
    repeat (4) @(posedge clk);
    irq = 1'b1;

    // 旧 RTL 在这里不会进入 mtvec；不能等到末尾 jal 才触发。
    repeat (16) @(posedge clk);
    if (!entered_mtvec) begin
        $display("FAIL: IRQ 仍依赖 branch/jump 才进入 mtvec");
        $finish;
    end

    wait (store_count == 3);
    @(posedge clk);
    if (store_value[0] !== 32'h8000_000b) begin
        $display("FAIL: external IRQ mcause 错误：%08x", store_value[0]);
        $finish;
    end
    if (dut.REGS[8] !== 32'h1234_5678) begin
        $display("FAIL: mret 后寄存器现场损坏");
        $finish;
    end

    $display("PASS: DarkRISCV 在直线指令边界响应 external IRQ");
    $finish;
end

initial begin
    repeat (2000) @(posedge clk);
    $display("TIMEOUT: DarkRISCV machine trap 测试未完成");
    $finish;
end

endmodule
