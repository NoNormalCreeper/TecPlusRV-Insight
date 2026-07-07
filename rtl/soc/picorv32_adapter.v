module picorv32_adapter #(
    parameter [31:0] STACKADDR = 32'hffff_ffff
) (
    input         clk,
    input         resetn,
    output        ifetch_valid,
    output [31:0] ifetch_addr,
    input         ifetch_ready,
    input  [31:0] ifetch_rdata,
    output        mem_valid,
    output        mem_instr,
    input         mem_ready,
    output [31:0] mem_addr,
    output [31:0] mem_wdata,
    output [3:0]  mem_wstrb,
    input  [31:0] mem_rdata,
    // SoC shell 的稳定计数器契约。
    // 这里必须保持为 CPU core 自己的计数结果，不要改回 top-level proxy counting。
    output [31:0] counter_cycle,
    output [31:0] counter_instret
);

wire unused_ifetch_ready;
wire [31:0] unused_ifetch_rdata;

assign ifetch_valid = 1'b0;
assign ifetch_addr = 32'h0000_0000;
assign unused_ifetch_ready = ifetch_ready;
assign unused_ifetch_rdata = ifetch_rdata;

picorv32 #(
    // ENABLE_COUNTERS 必须保持打开。
    // MiniSoC 的 MMIO counter 读数要求直接反映 core 自己的计数，而不是 SoC 侧估算值。
    .ENABLE_COUNTERS(1),
    .ENABLE_COUNTERS64(0),
    .ENABLE_REGS_DUALPORT(0),
    .TWO_STAGE_SHIFT(1),
    .BARREL_SHIFTER(0),
    .COMPRESSED_ISA(0),
    .ENABLE_PCPI(0),
    .ENABLE_MUL(0),
    .ENABLE_FAST_MUL(0),
    .ENABLE_DIV(0),
    .ENABLE_IRQ(0),
    .ENABLE_TRACE(0),
    .PROGADDR_RESET(32'h0000_0000),
    .STACKADDR(STACKADDR)
) u_cpu (
    .clk(clk),
    .resetn(resetn),
    .trap(),
    .mem_valid(mem_valid),
    .mem_instr(mem_instr),
    .mem_ready(mem_ready),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(mem_rdata),
    .pcpi_wr(1'b0),
    .pcpi_rd(32'h0000_0000),
    .pcpi_wait(1'b0),
    .pcpi_ready(1'b0),
    .irq(32'h0000_0000),
    .eoi(),
    .trace_valid(),
    .trace_data(),
    .counter_cycle(counter_cycle),
    .counter_instret(counter_instret)
);

endmodule
