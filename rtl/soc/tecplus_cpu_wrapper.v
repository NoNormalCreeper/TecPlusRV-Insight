module tecplus_cpu_wrapper #(
    parameter integer CPU_IMPL = 0,
    parameter [31:0] STACKADDR = 32'hffff_ffff
) (
    input         clk,
    input         resetn,
    input         irq_external,
    input         irq_timer,
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
    // wrapper 层契约：
    // 每个 CPU 实现都必须通过这两个输出提供 counter，这样 SoC 其余部分不需要再去偷看 per-core 内部信号。
    output [31:0] counter_cycle,
    output [31:0] counter_instret
);

localparam integer CPU_IMPL_PICORV32 = 0;
localparam integer CPU_IMPL_DARKRISCV = 1;

generate
    if (CPU_IMPL == CPU_IMPL_DARKRISCV) begin : g_darkriscv
        darkriscv_adapter u_cpu (
            .clk(clk),
            .resetn(resetn),
            .irq_external(irq_external),
            .irq_timer(irq_timer),
            .ifetch_valid(ifetch_valid),
            .ifetch_addr(ifetch_addr),
            .ifetch_ready(ifetch_ready),
            .ifetch_rdata(ifetch_rdata),
            .mem_valid(mem_valid),
            .mem_instr(mem_instr),
            .mem_ready(mem_ready),
            .mem_addr(mem_addr),
            .mem_wdata(mem_wdata),
            .mem_wstrb(mem_wstrb),
            .mem_rdata(mem_rdata),
            .counter_cycle(counter_cycle),
            .counter_instret(counter_instret)
        );
    end else begin : g_picorv32
        // PicoRV32 profile 暂不启用 IRQ；保留 wrapper 端口以稳定 SoC 契约。
        wire unused_irq = irq_external | irq_timer;

        picorv32_adapter #(
            .STACKADDR(STACKADDR)
        ) u_cpu (
            .clk(clk),
            .resetn(resetn),
            .ifetch_valid(ifetch_valid),
            .ifetch_addr(ifetch_addr),
            .ifetch_ready(ifetch_ready),
            .ifetch_rdata(ifetch_rdata),
            .mem_valid(mem_valid),
            .mem_instr(mem_instr),
            .mem_ready(mem_ready),
            .mem_addr(mem_addr),
            .mem_wdata(mem_wdata),
            .mem_wstrb(mem_wstrb),
            .mem_rdata(mem_rdata),
            .counter_cycle(counter_cycle),
            .counter_instret(counter_instret)
        );
    end
endgenerate

endmodule
