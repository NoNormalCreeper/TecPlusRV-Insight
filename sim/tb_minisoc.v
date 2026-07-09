// MiniSoC 通用回归 testbench。
// 默认只检查最小软件可见结果（test_exit / 最终 LED），
// 可通过参数把 UART / GPIO / exit write requirement 打开，升级成 board-top smoke。
`timescale 1ns/1ps

module tb_minisoc #(
    parameter integer CPU_IMPL = 0,
    parameter [31:0] EXPECT_EXIT_CODE = 32'h0000_0001,
    parameter [3:0]  EXPECT_LED = 4'h5,
    parameter integer REQUIRE_UART_WRITE = 0,
    parameter integer REQUIRE_LED_WRITE = 0,
    parameter integer REQUIRE_EXIT_WRITE = 0,
    parameter integer EXPECT_UART_FIRE_COUNT = -1,
    parameter integer DRIVE_UART_RX = 0,
    parameter [7:0] UART_RX_BYTE = 8'h00,
    parameter integer EXPECT_UART_LAST_BYTE = -1,
    parameter integer REQUIRE_TRAFFIC_WRITE = 0,
    parameter integer EXPECT_TRAFFIC = -1,
    parameter integer REQUIRE_BUZZER_WRITE = 0,
    parameter integer REQUIRE_BUZZER_TOGGLE = 0,
    parameter integer TIMEOUT_CYCLES = 2000000
);

reg clk;
reg reset;
reg [3:0] key;
reg uart_rxd;

reg uart_written;
reg led_written;
reg exit_written;
reg traffic_written;
reg buzzer_written;
integer uart_fire_count;
integer buzzer_toggle_count;
reg [7:0] uart_last_byte;
reg last_spk;

wire [3:0] led;
wire uart_txd;
wire [11:0] tl;
wire spk;


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

    uart_written = 1'b0;
    led_written = 1'b0;
    exit_written = 1'b0;
    traffic_written = 1'b0;
    buzzer_written = 1'b0;
    uart_fire_count = 0;
    buzzer_toggle_count = 0;
    uart_last_byte = 8'h00;
    last_spk = 1'b0;

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
    repeat (TIMEOUT_CYCLES) begin
        @(posedge clk);
        if (dut.uart_fire) begin
            uart_written = 1'b1;
            uart_fire_count = uart_fire_count + 1;
            uart_last_byte = dut.req_wdata[7:0];
        end
        if (dut.gpio_led_sel && (dut.req_wstrb != 4'b0))
            led_written = 1'b1;
        if (dut.test_exit_write)
            exit_written = 1'b1;
        if (dut.traffic_write)
            traffic_written = 1'b1;
        if (dut.buzzer_ctrl_write || dut.buzzer_period_write)
            buzzer_written = 1'b1;
        if (spk != last_spk) begin
            buzzer_toggle_count = buzzer_toggle_count + 1;
            last_spk = spk;
        end
        if (dut.test_exited) begin
            if (dut.test_exit_code !== EXPECT_EXIT_CODE) begin
                $display("FAIL: test_exit=0x%08x", dut.test_exit_code);
                $finish;
            end

            if (led !== EXPECT_LED) begin
                $display("FAIL: firmware LED write did not reach board pins, led=0x%0x", led);
                $finish;
            end

            if (REQUIRE_UART_WRITE != 0 && !uart_written) begin
                $display("FAIL: No UART write occurred during firmware execution");
                $finish;
            end

            if (EXPECT_UART_FIRE_COUNT >= 0 && uart_fire_count !== EXPECT_UART_FIRE_COUNT) begin
                $display("FAIL: expected %0d UART writes, got %0d", EXPECT_UART_FIRE_COUNT, uart_fire_count);
                $finish;
            end

            if (EXPECT_UART_LAST_BYTE >= 0 && uart_last_byte !== EXPECT_UART_LAST_BYTE[7:0]) begin
                $display("FAIL: expected UART last byte %02x, got %02x", EXPECT_UART_LAST_BYTE[7:0], uart_last_byte);
                $finish;
            end

            if (EXPECT_TRAFFIC >= 0 && tl !== EXPECT_TRAFFIC[11:0]) begin
                $display("FAIL: expected traffic pattern %03x, got %03x", EXPECT_TRAFFIC[11:0], tl);
                $finish;
            end

            if (REQUIRE_LED_WRITE != 0 && !led_written) begin
                $display("FAIL: No GPIO LED write occurred during firmware execution");
                $finish;
            end

            if (REQUIRE_EXIT_WRITE != 0 && !exit_written) begin
                $display("FAIL: exited but no exit written");
                $finish;
            end

            if (REQUIRE_TRAFFIC_WRITE != 0 && !traffic_written) begin
                $display("FAIL: No traffic-light MMIO write occurred");
                $finish;
            end

            if (REQUIRE_BUZZER_WRITE != 0 && !buzzer_written) begin
                $display("FAIL: No buzzer MMIO write occurred");
                $finish;
            end

            if (REQUIRE_BUZZER_TOGGLE != 0 && buzzer_toggle_count == 0) begin
                $display("FAIL: Buzzer was programmed but SPK never toggled");
                $finish;
            end

            $display("PASS: MiniSoC booted firmware through board top");
            $finish;
        end
    end

    $display("TIMEOUT: MiniSoC did not reach test_exit");
    $finish;
end

// ---- UART 监听器：把 CPU 打到 uart_txd 上的 8N1 帧还原成字符打印 ----
// 这样仿真终端能直接看到 firmware 的 boot log、自检结果和性能报告，
// 而不只是最后的 PASS/FAIL。仅用于仿真观测，不参与 PASS 判定。
//
// 时序换算：tb 用 CLK_FREQ=1MHz / BAUD=100kHz，即每个 bit 占 10 个时钟；
// 时钟周期 10ns（#5 翻转），所以 1 个 bit = 100ns。
localparam integer UART_CLKS_PER_BIT = 1000000 / 100000; // 10 个时钟/bit
localparam integer UART_CLK_PERIOD_NS = 10;              // 时钟周期 10ns
localparam integer UART_BIT_NS = UART_CLKS_PER_BIT * UART_CLK_PERIOD_NS; // 100ns

integer uart_bit_i;
reg [7:0] uart_rx_byte;

task drive_uart_rx_byte;
    input [7:0] value;
    integer rx_bit_i;
    begin
        @(negedge clk);
        uart_rxd = 1'b0;
        repeat (UART_CLKS_PER_BIT) @(posedge clk);

        for (rx_bit_i = 0; rx_bit_i < 8; rx_bit_i = rx_bit_i + 1) begin
            @(negedge clk);
            uart_rxd = value[rx_bit_i];
            repeat (UART_CLKS_PER_BIT) @(posedge clk);
        end

        @(negedge clk);
        uart_rxd = 1'b1;
        repeat (UART_CLKS_PER_BIT) @(posedge clk);
    end
endtask

initial begin
    wait (reset === 1'b1);
    if (DRIVE_UART_RX != 0) begin
        repeat (100) @(posedge clk);
        drive_uart_rx_byte(UART_RX_BYTE);
    end
end

initial begin
    forever begin
        // 空闲时线是高电平，等一个下降沿 = 起始位到来。
        @(negedge uart_txd);
        // 跳到第 0 个数据位的正中间采样（起始位 1 个 + 半个 bit）。
        #(UART_BIT_NS + UART_BIT_NS / 2);
        for (uart_bit_i = 0; uart_bit_i < 8; uart_bit_i = uart_bit_i + 1) begin
            uart_rx_byte[uart_bit_i] = uart_txd; // LSB 先到
            #(UART_BIT_NS);
        end
        // 一帧收全，直接把字符打到终端（stop 位不用再等）。
        $write("%c", uart_rx_byte);
        $fflush;
    end
end

endmodule
