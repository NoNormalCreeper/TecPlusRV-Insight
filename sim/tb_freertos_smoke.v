// FreeRTOS MiniSoC 通用 smoke bench：同时检查 firmware 结果和 CPU 确实进入 task。
`timescale 1ns/1ps

module tb_freertos_smoke #(
    parameter integer CPU_IMPL = 1,
    parameter FIRMWARE_MEM_FILE = "firmware/build/firmware.mem",
    parameter [31:0] TASK_PC_START = 32'h0000_0000,
    parameter [31:0] TASK_PC_END = 32'h0000_0000,
    parameter [31:0] TRAP_PC_START = 32'h0000_0000,
    parameter integer MIN_ECALL_TRAPS = 0,
    parameter [31:0] EXPECT_EXIT_CODE = 32'h0000_0001,
    parameter integer TIMEOUT_CYCLES = 2000000
);

reg clk;
reg reset;
reg [3:0] key;
reg uart_rxd;
reg task_seen;
reg trap_entry_active;
reg ecall_pending_return;
reg [31:0] ecall_pc;
integer cycle_count;
integer ecall_trap_count;

wire [3:0] led;
wire uart_txd;
wire [11:0] tl;
wire spk;

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
    .spk(spk)
);

always #5 clk = ~clk;

initial begin
    clk = 1'b0;
    reset = 1'b0;
    key = 4'b1111;
    uart_rxd = 1'b1;
    task_seen = 1'b0;
    trap_entry_active = 1'b0;
    ecall_pending_return = 1'b0;
    ecall_pc = 32'h0000_0000;
    cycle_count = 0;
    ecall_trap_count = 0;
    repeat (5) @(posedge clk);
    reset = 1'b1;
end

always @(posedge clk) begin
    cycle_count = cycle_count + 1;

    if (dut.u_cpu.g_darkriscv.u_cpu.u_cpu.PC >= TASK_PC_START &&
            dut.u_cpu.g_darkriscv.u_cpu.u_cpu.PC < TASK_PC_END) begin
        task_seen = 1'b1;
    end

    if (dut.u_cpu.g_darkriscv.u_cpu.u_cpu.PC == TRAP_PC_START) begin
        if (!trap_entry_active &&
                dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MCAUSE == 32'h0000_000b) begin
            ecall_trap_count = ecall_trap_count + 1;
            ecall_pc = dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MEPC;
            ecall_pending_return = 1'b1;
        end
        trap_entry_active = 1'b1;
    end else begin
        trap_entry_active = 1'b0;
    end

    if (dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MRET && ecall_pending_return) begin
        if (dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MEPC == ecall_pc) begin
            $display("FAIL: ecall 返回地址未推进，mepc=%08x", ecall_pc);
            $finish;
        end
        ecall_pending_return = 1'b0;
    end

    if (dut.test_exited) begin
        if (dut.test_exit_code !== EXPECT_EXIT_CODE) begin
            $display("FAIL: FreeRTOS firmware 错误码=%08x", dut.test_exit_code);
            $finish;
        end
        if (!task_seen) begin
            $display("FAIL: test_exit 前 CPU PC 未进入 task symbol 区间");
            $finish;
        end
        if (ecall_trap_count < MIN_ECALL_TRAPS) begin
            $display("FAIL: ecall trap 次数不足：%0d < %0d",
                ecall_trap_count, MIN_ECALL_TRAPS);
            $finish;
        end
        if (MIN_ECALL_TRAPS != 0) begin
            $display("PASS: FreeRTOS 主动切换完成，ecall traps=%0d",
                ecall_trap_count);
        end else begin
            $display("PASS: FreeRTOS 首任务已从 canonical frame 启动");
        end
        $finish;
    end

    if (cycle_count >= TIMEOUT_CYCLES) begin
        $display("TIMEOUT: FreeRTOS 首任务未完成 pc=%08x mepc=%08x mcause=%08x ecall=%0d",
            dut.u_cpu.g_darkriscv.u_cpu.u_cpu.PC,
            dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MEPC,
            dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MCAUSE,
            ecall_trap_count);
        $finish;
    end
end

endmodule
