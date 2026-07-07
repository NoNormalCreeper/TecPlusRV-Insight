// MiniSoC board-top smoke test.
// It runs the same board-level top intended for ISE, then watches the firmware
// write test_exit. This keeps the simulation path honest: CPU, BRAM, TinyBus,
// LED, and UART TX are connected through the same wrapper.
`timescale 1ns/1ps

module tb_minisoc;

reg clk;
reg reset;
reg [3:0] key;

reg uart_written;
reg led_written;
reg exit_written;

wire [3:0] led;
wire uart_txd;


tecplus_minisoc_top #(
    .CLK_FREQ(1000000),
    .UART_BAUD(100000),
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

    uart_written = 1'b0;
    led_written = 1'b0;
    exit_written = 1'b0;

    $dumpfile("sim/build/tb_minisoc.vcd");
    $dumpvars(0, tb_minisoc);

    repeat (5) @(posedge clk);
    reset = 1'b1;
end

initial begin
    if (dut.BRAM_ADDR_WIDTH !== 14) begin
        $display("FAIL: MiniSoC BRAM should expose a 64 KiB word-addressed window");
        $finish;
    end
end

initial begin
    repeat (500000) begin
        @(posedge clk);
        if (dut.uart_fire)
            uart_written = 1'b1;
        if (dut.gpio_led_sel && (dut.req_wstrb != 4'b0))
            led_written = 1'b1;
        if (dut.test_exit_write)
            exit_written = 1'b1;
        if (dut.test_exited) begin
            if (dut.test_exit_code !== 32'h0000_0001) begin
                $display("FAIL: test_exit=0x%08x", dut.test_exit_code);
                $finish;
            end

            if (led !== 4'h5) begin
                $display("FAIL: firmware LED write did not reach board pins, led=0x%0x", led);
                $finish;
            end

            if (!uart_written) begin
                $display("FAIL: No UART write occurred during firmware execution");
                $finish;
            end

            if (!led_written) begin
                $display("FAIL: No GPIO LED write occurred during firmware execution");
                $finish;
            end

            if (!exit_written) begin
                $display("FAIL: exited but no exit written");
                $finish;
            end

            $display("PASS: MiniSoC booted firmware through board top");
            $finish;
        end
    end

    $display("TIMEOUT: MiniSoC did not reach test_exit");
    $finish;
end

endmodule
