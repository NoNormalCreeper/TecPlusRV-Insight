`timescale 1ns/1ps

module tb_minisoc_perf #(
    parameter integer CPU_IMPL = 0,
    parameter [31:0] EXPECT_EXIT_CODE = 32'h0000_0001,
    parameter integer TIMEOUT_CYCLES = 2000000
);

reg clk;
reg reset;
reg [3:0] key;

wire [3:0] led;
wire uart_txd;

integer cpi_x1000;

tecplus_minisoc_top #(
    .CLK_FREQ(1000000),
    .UART_BAUD(100000),
    .CPU_IMPL(CPU_IMPL),
    .BRAM_ADDR_WIDTH(14),
    .BRAM_INIT_FILE("firmware/build/firmware.mem")
) dut (
    .clk(clk),
    .reset(reset),
    .key(key),
    .led(led),
    .uart_rxd(1'b1),
    .uart_txd(uart_txd)
);

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

            if (dut.instret_count == 32'h0000_0000) begin
                $display("FAIL: instret_count stayed zero");
                $finish;
            end

            cpi_x1000 = (dut.cycle_count * 1000) / dut.instret_count;
            $display("RESULT: cpu_impl=%0d cycles=%0d instret=%0d cpi_x1000=%0d", CPU_IMPL, dut.cycle_count, dut.instret_count, cpi_x1000);
            $display("PASS: MiniSoC perf measurement completed");
            $finish;
        end
    end

    $display("TIMEOUT: MiniSoC perf test did not reach test_exit");
    $finish;
end

endmodule
