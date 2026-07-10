// DarkRISCV machine trap core-level 定向测试。
// 覆盖独立 IRQ 进入、MEI/MTI 优先级、CSR 掩码、ecall/ebreak 和 mret。
`timescale 1ns/1ps

module tb_darkriscv_machine_trap #(
    parameter FIRMWARE_MEM_FILE = "sim/build/darkriscv_machine_trap.mem"
);

reg clk;
reg reset;
reg irq;
reg timer_irq;
reg [31:0] imem [0:16383];
reg [31:0] store_value [0:11];
reg [31:0] last_store_addr;
integer store_count;
integer trap_entries;
integer i;

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
wire esimack;

wire [31:0] idata = imem[iaddr[15:2]];

darkriscv dut (
    .CLK(clk),
    .RES(reset),
    .IRQ(irq),
    .MTIP(timer_irq),
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
    .ESIMREQ(1'b0),
    .ESIMACK(esimack),
    .PERF_CYCLE(perf_cycle),
    .PERF_INSTRET(perf_instret),
    .DEBUG(debug)
);

always #5 clk = ~clk;

always @(posedge clk) begin
    if (!reset && iaddr == 32'h0000_0200) begin
        trap_entries <= trap_entries + 1;
    end

    if (ddreq && dwr && (store_count == 0 || daddr != last_store_addr)) begin
        if (store_count < 12) begin
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
    timer_irq = 1'b0;
    store_count = 0;
    trap_entries = 0;
    last_store_addr = 32'hffff_ffff;
    for (i = 0; i < 12; i = i + 1) begin
        store_value[i] = 32'h0000_0000;
    end
    $readmemh(FIRMWARE_MEM_FILE, imem);

    // DarkRISCV 的 register file 通过 reset pipeline 逐拍落定，多留几拍消除 X。
    repeat (8) @(posedge clk);
    reset = 1'b0;

    // s0 的 signature 出现后仍处于连续 addi 的前段。
    wait (dut.REGS[8] == 32'h1234_5678);
    if (dut.MTVEC !== 32'h0000_0200 || dut.MIE !== 32'h0000_0000 ||
        dut.MSTATUS !== 32'h0000_1800) begin
        $display("FAIL: machine CSR reset/mask 错误 mtvec=%08x mie=%08x mstatus=%08x",
            dut.MTVEC, dut.MIE, dut.MSTATUS);
        $finish;
    end

    irq = 1'b1;
    timer_irq = 1'b1;
    repeat (2) @(posedge clk);
    #1;
    if ((dut.MIP & 32'h0000_0880) !== 32'h0000_0880 || trap_entries != 0) begin
        $display("FAIL: mip 未反映 raw pending，或 enable 关闭时错误进入 trap");
        $finish;
    end

    wait (dut.MIE == 32'h0000_0880 && dut.MSTATUS == 32'h0000_1888);

    // 两种 IRQ 同时 pending 时必须优先响应 MEI，且不能等待末尾 jal。
    for (i = 0; i < 16 && trap_entries == 0; i = i + 1) begin
        @(posedge clk);
    end
    if (trap_entries == 0) begin
        $display("FAIL: IRQ 仍依赖 branch/jump 才进入 mtvec");
        $finish;
    end
    irq = 1'b0;
    timer_irq = 1'b0;

    wait (store_count == 3);
    @(posedge clk);
    if (store_value[0] !== 32'h8000_000b) begin
        $display("FAIL: external IRQ mcause 错误：%08x", store_value[0]);
        $finish;
    end

    // firmware 会继续执行 ecall 与 ebreak；两者都必须返回下一条指令。
    wait (store_count >= 9);
    @(posedge clk);
    if (store_value[3] !== 32'h0000_000b || store_value[6] !== 32'h0000_0003) begin
        $display("FAIL: 同步 trap cause 错误 ecall=%08x ebreak=%08x",
            store_value[3], store_value[6]);
        $finish;
    end
    if (store_value[7] !== store_value[4] + 32'd4) begin
        $display("FAIL: ecall 返回后未执行紧随其后的 ebreak");
        $finish;
    end
    if (dut.REGS[9] !== 32'd32) begin
        $display("FAIL: external IRQ 返回后直线指令重复或丢失：s1=%0d", dut.REGS[9]);
        $finish;
    end

    wait (dut.MIE[7] && dut.MSTATUS[3]);
    timer_irq = 1'b1;
    for (i = 0; i < 16 && trap_entries < 4; i = i + 1) begin
        @(posedge clk);
    end
    if (trap_entries < 4) begin
        $display("FAIL: timer IRQ 未在完整指令边界进入 mtvec");
        $finish;
    end
    timer_irq = 1'b0;

    wait (store_count == 12);
    wait (dut.REGS[18] == 32'd16);
    if (store_value[9] !== 32'h8000_0007 ||
        store_value[2] !== 32'd1 || store_value[5] !== 32'd2 ||
        store_value[8] !== 32'd3 || store_value[11] !== 32'd4) begin
        $display("FAIL: trap 记录顺序或 timer cause 错误");
        $finish;
    end
    if (dut.REGS[8] !== 32'h1234_5678) begin
        $display("FAIL: trap/mret 后寄存器 signature 损坏");
        $finish;
    end

    $display("PASS: DarkRISCV machine trap/CSR/mret 基础语义通过");
    $finish;
end

initial begin
    repeat (2000) @(posedge clk);
    $display("TIMEOUT: DarkRISCV machine trap 测试未完成");
    $finish;
end

endmodule
