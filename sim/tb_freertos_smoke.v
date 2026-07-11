// FreeRTOS MiniSoC 通用 smoke bench：同时检查 firmware 结果和 CPU 确实进入 task。
`timescale 1ns/1ps

module tb_freertos_smoke #(
    parameter integer CPU_IMPL = 1,
    parameter FIRMWARE_MEM_FILE = "firmware/build/firmware.mem",
    parameter [31:0] TASK_PC_START = 32'h0000_0000,
    parameter [31:0] TASK_PC_END = 32'h0000_0000,
    parameter [31:0] EXPECT_EXIT_CODE = 32'h0000_0001,
    parameter integer TIMEOUT_CYCLES = 2000000
);

reg clk;
reg reset;
reg [3:0] key;
reg uart_rxd;
reg task_seen;
integer cycle_count;

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
    cycle_count = 0;
    repeat (5) @(posedge clk);
    reset = 1'b1;
end

always @(posedge clk) begin
    cycle_count = cycle_count + 1;

    if (dut.u_cpu.g_darkriscv.u_cpu.u_cpu.PC >= TASK_PC_START &&
            dut.u_cpu.g_darkriscv.u_cpu.u_cpu.PC < TASK_PC_END) begin
        task_seen = 1'b1;
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
        $display("PASS: FreeRTOS 首任务已从 canonical frame 启动");
        $finish;
    end

    if (cycle_count >= TIMEOUT_CYCLES) begin
        $display("TIMEOUT: FreeRTOS 首任务未完成 pc=%08x mepc=%08x mcause=%08x",
            dut.u_cpu.g_darkriscv.u_cpu.u_cpu.PC,
            dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MEPC,
            dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MCAUSE);
        $finish;
    end
end

endmodule
