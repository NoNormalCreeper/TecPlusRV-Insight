`timescale 1ns/1ps

module tb_minisoc_counter_source #(
    parameter integer CPU_IMPL = 0,
    parameter FIRMWARE_MEM_FILE = "firmware/build/firmware.mem",
    parameter [31:0] EXPECT_EXIT_CODE = 32'h0000_0001,
    parameter integer TIMEOUT_CYCLES = 2000000
);

reg clk;
reg reset;
reg [3:0] key;

wire [3:0] led;
wire uart_txd;
wire [31:0] core_cycle_backing;
wire [31:0] core_instret_backing;

tecplus_minisoc_top #(
    .CLK_FREQ(1000000),
    .UART_BAUD(100000),
    .CPU_IMPL(CPU_IMPL),
    .BRAM_ADDR_WIDTH(14),
    .BOOTLOADER_ENABLE(0),
    .BRAM_INIT_FILE(FIRMWARE_MEM_FILE)
) dut (
    .clk(clk),
    .reset(reset),
    .key(key),
    .led(led),
    .uart_rxd(1'b1),
    .uart_txd(uart_txd)
);

generate
    if (CPU_IMPL == 0) begin : g_pico_backing
        assign core_cycle_backing = dut.u_cpu.g_picorv32.u_cpu.u_cpu.count_cycle[31:0];
        assign core_instret_backing = dut.u_cpu.g_picorv32.u_cpu.u_cpu.count_instr[31:0];
    end else begin : g_dark_backing
        assign core_cycle_backing = dut.u_cpu.g_darkriscv.u_cpu.u_cpu.CSRCLK[31:0];
        assign core_instret_backing = dut.u_cpu.g_darkriscv.u_cpu.u_cpu.CSRINS[31:0];
    end
endgenerate

always #5 clk = ~clk;

initial begin
    clk = 1'b0;
    reset = 1'b0;
    key = 4'b1111;

    repeat (5) @(posedge clk);
    reset = 1'b1;
end

initial begin
    repeat (TIMEOUT_CYCLES) begin
        @(posedge clk);
        if (dut.test_exited) begin
            if (dut.test_exit_code !== EXPECT_EXIT_CODE) begin
                $display("FAIL: test_exit=0x%08x", dut.test_exit_code);
                $finish;
            end

            if (^core_cycle_backing === 1'bx) begin
                $display("FAIL: 核内 cycle backing counter 出现未知值");
                $finish;
            end

            if (^core_instret_backing === 1'bx) begin
                $display("FAIL: 核内 instret backing counter 出现未知值");
                $finish;
            end

            if (dut.cycle_rdata !== core_cycle_backing) begin
                $display("FAIL: cycle MMIO 不一致 mmio=%0d core=%0d", dut.cycle_rdata, core_cycle_backing);
                $finish;
            end

            if (dut.instret_rdata !== core_instret_backing) begin
                $display("FAIL: instret MMIO 不一致 mmio=%0d core=%0d", dut.instret_rdata, core_instret_backing);
                $finish;
            end

            if (dut.mem_wait_rdata == 32'h0000_0000) begin
                $display("FAIL: SoC 数据等待计数器没有记录任何等待周期");
                $finish;
            end

            $display("PASS: core-backed counter 一致，SoC mem_wait=%0d", dut.mem_wait_rdata);
            $finish;
        end
    end

    $display("TIMEOUT: MiniSoC counter source test did not reach test_exit");
    $finish;
end

endmodule
