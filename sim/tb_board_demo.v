// board_demo 专用 testbench：验证短时综合巡检真的覆盖 SDRAM 和主要板级外设。
`timescale 1ns/1ps

module tb_board_demo #(
    parameter integer CPU_IMPL = 0,
    parameter FIRMWARE_MEM_FILE = "firmware/build/firmware.mem",
    parameter [31:0] EXPECT_EXIT_CODE = 32'h0000_0001,
    parameter [3:0]  EXPECT_FINAL_LED = 4'h5,
    parameter integer MIN_LED_WRITES = 4,
    parameter integer MIN_UART_WRITES = 4,
    parameter integer TIMEOUT_CYCLES = 3000000
);

reg clk;
reg reset;
reg [3:0] key;

integer led_write_count;
integer uart_write_count;
integer traffic_write_count;
integer buzzer_write_count;
integer vga_write_count;
integer sdram_read_count;
integer sdram_write_count;

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
wire [31:0] model_read_command_count;
wire [31:0] model_write_command_count;

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
    .read_command_count(model_read_command_count),
    .write_command_count(model_write_command_count)
);

always #5 clk = ~clk;

initial begin
    clk = 1'b0;
    reset = 1'b0;
    key = 4'b1111;
    led_write_count = 0;
    uart_write_count = 0;
    traffic_write_count = 0;
    buzzer_write_count = 0;
    vga_write_count = 0;
    sdram_read_count = 0;
    sdram_write_count = 0;

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

        if (dut.traffic_write)
            traffic_write_count = traffic_write_count + 1;

        if (dut.buzzer_ctrl_write || dut.buzzer_period_write)
            buzzer_write_count = buzzer_write_count + 1;

        if (dut.vga_bitmap_write)
            vga_write_count = vga_write_count + 1;

        if (dut.sdram_req_fire) begin
            if (dut.req_we_reg)
                sdram_write_count = sdram_write_count + 1;
            else
                sdram_read_count = sdram_read_count + 1;
        end

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

            if (traffic_write_count == 0 || tl !== 12'h249) begin
                $display("FAIL: board_demo traffic writes=%0d final=%03x", traffic_write_count, tl);
                $finish;
            end

            if (buzzer_write_count < 3 || spk !== 1'b0) begin
                $display("FAIL: board_demo buzzer writes=%0d spk=%b", buzzer_write_count, spk);
                $finish;
            end

            if (vga_write_count < 96 ||
                dut.g_vga_bitmap.u_vga_bitmap.framebuffer[0] !== 32'hffff_ffff ||
                dut.g_vga_bitmap.u_vga_bitmap.framebuffer[2] !== 32'h8000_0001 ||
                dut.g_vga_bitmap.u_vga_bitmap.framebuffer[48] !== 32'hffff_ffff ||
                dut.g_vga_bitmap.u_vga_bitmap.framebuffer[95] !== 32'hffff_ffff) begin
                $display("FAIL: board_demo VGA writes=%0d pattern mismatch", vga_write_count);
                $finish;
            end

            if (sdram_read_count == 0 || sdram_write_count == 0) begin
                $display("FAIL: board_demo SDRAM read=%0d write=%0d", sdram_read_count, sdram_write_count);
                $finish;
            end

            if (led !== EXPECT_FINAL_LED) begin
                $display("FAIL: board_demo final LED=0x%0x expected=0x%0x", led, EXPECT_FINAL_LED);
                $finish;
            end

            $display("PASS: board_demo 综合巡检通过 uart=%0d sdram=%0d/%0d vga=%0d",
                     uart_write_count, sdram_read_count, sdram_write_count, vga_write_count);
            $finish;
        end
    end

    $display("TIMEOUT: board_demo did not reach test_exit");
    $finish;
end

endmodule
