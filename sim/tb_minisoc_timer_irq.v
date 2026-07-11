// DarkRISCV timer IRQ、data stall 精确返回与 spurious pending 端到端回归。
`timescale 1ns/1ps

module tb_minisoc_timer_irq #(
    parameter integer CPU_IMPL = 1,
    parameter FIRMWARE_MEM_FILE = "firmware/build/firmware.mem",
    parameter integer TIMEOUT_CYCLES = 100000
);

reg clk;
reg reset;
reg [3:0] key;
reg uart_rxd;
integer cycle_count;
integer timer_entry_count;
reg stall_injected;
reg stall_active;
reg irq_pending_during_stall;
reg spurious_injected;

wire [3:0] led;
wire uart_txd;
wire [11:0] tl;
wire spk;
wire sh_clk;
wire sh_cke;
wire sh_ncs;
wire sh_nwe;
wire sh_ncas;
wire sh_nras;
wire [1:0] sh_dqm;
wire [1:0] sh_ba;
wire [12:0] sh_a;
wire [15:0] sh_db;

tecplus_minisoc_top #(
    .CLK_FREQ(1000000),
    .UART_BAUD(100000),
    .CPU_IMPL(CPU_IMPL),
    .BRAM_ADDR_WIDTH(14),
    .BRAM_INIT_FILE(FIRMWARE_MEM_FILE)
) dut (
    .clk(clk),
    .reset(reset),
    .key(key),
    .led(led),
    .uart_rxd(uart_rxd),
    .uart_txd(uart_txd),
    .tl(tl),
    .spk(spk),
    .sh_clk(sh_clk),
    .sh_cke(sh_cke),
    .sh_ncs(sh_ncs),
    .sh_nwe(sh_nwe),
    .sh_ncas(sh_ncas),
    .sh_nras(sh_nras),
    .sh_dqm(sh_dqm),
    .sh_ba(sh_ba),
    .sh_a(sh_a),
    .sh_db(sh_db)
);

sdram_x16_model model (
    .clk(clk),
    .reset(!reset),
    .cke(sh_cke),
    .cs_n(sh_ncs),
    .ras_n(sh_nras),
    .cas_n(sh_ncas),
    .we_n(sh_nwe),
    .dqm(sh_dqm),
    .ba(sh_ba),
    .addr(sh_a),
    .dq(sh_db),
    .read_command_count(),
    .write_command_count()
);

always #5 clk = ~clk;

initial begin
    clk = 1'b0;
    reset = 1'b0;
    key = 4'b1111;
    uart_rxd = 1'b1;
    cycle_count = 0;
    timer_entry_count = 0;
    stall_injected = 1'b0;
    stall_active = 1'b0;
    irq_pending_during_stall = 1'b0;
    spurious_injected = 1'b0;
    repeat (5) @(posedge clk);
    reset = 1'b1;
end

always @(posedge clk) begin
    cycle_count = cycle_count + 1;
    if (dut.u_cpu.g_darkriscv.u_cpu.u_cpu.IREQ) begin
        if (stall_active) begin
            $display("FAIL: data transaction 完成前进入 timer trap");
            $finish;
        end
        timer_entry_count = timer_entry_count + 1;
    end

    if (cycle_count >= TIMEOUT_CYCLES) begin
        $display("TIMEOUT: DarkRISCV timer IRQ 回归未完成 pc=%08x mepc=%08x mcause=%08x mstatus=%08x mie=%08x mip=%08x",
            dut.u_cpu.g_darkriscv.u_cpu.u_cpu.PC,
            dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MEPC,
            dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MCAUSE,
            dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MSTATUS,
            dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MIE,
            dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MIP);
        $display("TIMEOUT: mtime=%08x_%08x mtimecmp=%08x_%08x irq=%0d pending=%0d respond=%0d req_addr=%08x traps=%0d stall=%0d irq_seen=%0d spurious=%0d",
            dut.mtime_hi_rdata, dut.mtime_lo_rdata,
            dut.mtimecmp_hi_rdata, dut.mtimecmp_lo_rdata,
            dut.machine_timer_irq, dut.pending, dut.respond, dut.req_addr,
            timer_entry_count, stall_injected, irq_pending_during_stall,
            spurious_injected);
        $finish;
    end

    if (dut.test_exited) begin
        if (dut.test_exit_code !== 32'h0000_0001) begin
            $display("FAIL: timer IRQ firmware 错误码=%08x", dut.test_exit_code);
            $finish;
        end
        if (!stall_injected || !irq_pending_during_stall || !spurious_injected) begin
            $display("FAIL: stall/spurious 注入未完整发生");
            $finish;
        end
        if (timer_entry_count < 3) begin
            $display("FAIL: timer trap 次数不足：%0d", timer_entry_count);
            $finish;
        end
        $display("PASS: DarkRISCV timer IRQ 在 memory stall 后精确返回");
        $finish;
    end
end

// MTIE/MIE 生效后，截住一次 BRAM data response，直到 MTIP 在 stall 中拉高。
initial begin
    wait (reset === 1'b1);
    wait (dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MIE[7] &&
          dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MSTATUS[3]);
    @(negedge clk);
    while (!(dut.pending && dut.req_is_bram && !dut.req_we_reg)) begin
        @(negedge clk);
    end
    force dut.respond = 1'b0;
    stall_injected = 1'b1;
    stall_active = 1'b1;
    while (!dut.machine_timer_irq) begin
        @(posedge clk);
    end
    irq_pending_during_stall = 1'b1;
    repeat (2) @(posedge clk);
    release dut.respond;
    stall_active = 1'b0;
end

// 第一次 handler 把 compare 推到未来后，额外保留一次 pending，模拟有限延迟撤销。
initial begin
    wait (timer_entry_count >= 1);
    wait (dut.mtimecmp_lo_write && dut.req_wdata != 32'hffff_ffff);
    @(negedge clk);
    force dut.machine_timer_irq = 1'b1;
    spurious_injected = 1'b1;
    wait (timer_entry_count >= 2);
    @(negedge clk);
    release dut.machine_timer_irq;
end

endmodule
