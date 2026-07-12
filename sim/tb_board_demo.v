// board_demo 专用 testbench。
// 这里不解码 UART 串口位流，只验证 SoC 侧确实发起了多次 UART/LED MMIO 写，
// 并且在首轮 demo 结束前把 LED 切到了 0x8，然后写出 test_exit=1。
`timescale 1ns/1ps

module tb_board_demo #(
    parameter integer CPU_IMPL = 0,
    parameter FIRMWARE_MEM_FILE = "firmware/build/firmware.mem",
    parameter [31:0] EXPECT_EXIT_CODE = 32'h0000_0001,
    parameter [3:0]  EXPECT_FINAL_LED = 4'h8,
    parameter integer MIN_LED_WRITES = 4,
    parameter integer MIN_UART_WRITES = 4,
    parameter integer TIMEOUT_CYCLES = 3000000
);

reg clk;
reg reset;
reg [3:0] key;

integer led_write_count;
integer uart_write_count;

wire [3:0] led;
wire uart_txd;

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

always #5 clk = ~clk;

initial begin
    clk = 1'b0;
    reset = 1'b0;
    key = 4'b1111;
    led_write_count = 0;
    uart_write_count = 0;

    $dumpfile("sim/build/tb_board_demo.vcd");
    $dumpvars(0, tb_board_demo);

    repeat (5) @(posedge clk);
    reset = 1'b1;
end

initial begin
    repeat (TIMEOUT_CYCLES) begin
        @(posedge clk);

        if (dut.gpio_led_sel && (dut.req_wstrb != 4'b0))
            led_write_count = led_write_count + 1;

        if (dut.uart_fire)
            uart_write_count = uart_write_count + 1;

        if (dut.test_exited) begin
            if (dut.test_exit_code !== EXPECT_EXIT_CODE) begin
                $display("FAIL: board_demo test_exit=0x%08x", dut.test_exit_code);
                $finish;
            end

            if (led_write_count < MIN_LED_WRITES) begin
                $display("FAIL: board_demo only wrote LED %0d times", led_write_count);
                $finish;
            end

            if (uart_write_count < MIN_UART_WRITES) begin
                $display("FAIL: board_demo only wrote UART %0d times", uart_write_count);
                $finish;
            end

            if (led !== EXPECT_FINAL_LED) begin
                $display("FAIL: board_demo final LED=0x%0x expected=0x%0x", led, EXPECT_FINAL_LED);
                $finish;
            end

            $display("PASS: board_demo completed first visible round");
            $finish;
        end
    end

    $display("TIMEOUT: board_demo did not reach test_exit");
    $finish;
end

endmodule
