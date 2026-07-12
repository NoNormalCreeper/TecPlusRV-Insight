// Bad Apple 最小 player 端到端仿真：真实 CPU 从预装 SDRAM 解析 BAM1 并驱动四类外设。
`timescale 1ns/1ps

module tb_bad_apple_minimal #(
    parameter integer CPU_IMPL = 0,
    parameter FIRMWARE_MEM_FILE = "firmware/build/bad_apple_minimal.mem",
    parameter ASSET_MEM_FILE = "firmware/assets/bad_apple_minimal.mem"
);

reg clk;
reg reset;
reg [3:0] key;
reg uart_rxd;
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

reg [31:0] asset_words [0:4095];
integer asset_word_count;
integer i;
integer cycles;
integer tile_write_count;
integer buzzer_write_count;
integer uart_write_count;
integer led_change_count;
reg [3:0] last_led;

tecplus_minisoc_top #(
    .CLK_FREQ(1000000),
    .UART_BAUD(100000),
    .CPU_IMPL(CPU_IMPL),
    .BRAM_ADDR_WIDTH(14),
    .BOOTLOADER_ENABLE(0),
    .VGA_TEXT_ENABLE(1),
    .VGA_BITMAP_ENABLE(0),
    .BRAM_INIT_FILE(FIRMWARE_MEM_FILE)
) dut (
    .clk(clk), .reset(reset), .key(key), .led(led),
    .uart_rxd(uart_rxd), .uart_txd(uart_txd), .tl(tl), .spk(spk),
    .sh_clk(sh_clk), .sh_cke(sh_cke), .sh_ncs(sh_ncs), .sh_nwe(sh_nwe),
    .sh_ncas(sh_ncas), .sh_nras(sh_nras), .sh_dqm(sh_dqm),
    .sh_ba(sh_ba), .sh_a(sh_a), .sh_db(sh_db)
);

// 缩短一帧，但保留足够周期让 440 Hz 对应的 PWM 在换音前发生翻转。
defparam dut.g_vga_text.u_vga_text.CLK_DIV = 1;
defparam dut.g_vga_text.u_vga_text.H_VISIBLE = 16;
defparam dut.g_vga_text.u_vga_text.H_FRONT = 1;
defparam dut.g_vga_text.u_vga_text.H_SYNC = 2;
defparam dut.g_vga_text.u_vga_text.H_BACK = 1;
defparam dut.g_vga_text.u_vga_text.V_VISIBLE = 16;
defparam dut.g_vga_text.u_vga_text.V_FRONT = 1;
defparam dut.g_vga_text.u_vga_text.V_SYNC = 1;
defparam dut.g_vga_text.u_vga_text.V_BACK = 82;

sdram_x16_model model (
    .clk(clk), .reset(!reset), .cke(sh_cke), .cs_n(sh_ncs),
    .ras_n(sh_nras), .cas_n(sh_ncas), .we_n(sh_nwe), .dqm(sh_dqm),
    .ba(sh_ba), .addr(sh_a), .dq(sh_db),
    .read_command_count(model_read_command_count),
    .write_command_count(model_write_command_count)
);

function [15:0] model_key;
    input [31:0] byte_addr;
    reg [4:0] row_key;
    begin
        row_key = byte_addr[16:12] ^ {4'b0000, byte_addr[24]};
        model_key = {row_key, byte_addr[11:10], byte_addr[9:1]};
    end
endfunction

always #5 clk = ~clk;

always @(posedge clk) begin
    if (reset) begin
        if (dut.vga_tile_write)
            tile_write_count = tile_write_count + 1;
        if (dut.buzzer_ctrl_write || dut.buzzer_period_write)
            buzzer_write_count = buzzer_write_count + 1;
        if (dut.uart_fire)
            uart_write_count = uart_write_count + 1;
        if (led != last_led) begin
            led_change_count = led_change_count + 1;
            last_led = led;
        end
    end
end

initial begin
    clk = 1'b0;
    reset = 1'b0;
    key = 4'b1111;
    uart_rxd = 1'b1;
    cycles = 0;
    tile_write_count = 0;
    buzzer_write_count = 0;
    uart_write_count = 0;
    led_change_count = 0;
    last_led = 4'h0;

    $readmemh(ASSET_MEM_FILE, asset_words);
    #2;
    asset_word_count = asset_words[2] / 4;
    for (i = 0; i < asset_word_count; i = i + 1) begin
        model.mem[model_key(32'h8100_0000 + i * 4)] = asset_words[i][15:0];
        model.mem[model_key(32'h8100_0002 + i * 4)] = asset_words[i][31:16];
    end

    repeat (5) @(posedge clk);
    reset = 1'b1;

    while (cycles < 2000000 &&
           !(dut.test_exited && tile_write_count > 300 &&
             buzzer_write_count >= 2 && uart_write_count >= 2 &&
             led_change_count >= 2 && spk == 1'b1)) begin
        @(posedge clk);
        cycles = cycles + 1;
    end

    if (!dut.test_exited || tile_write_count <= 300 || buzzer_write_count < 2 ||
        uart_write_count < 2 || led_change_count < 2 || spk != 1'b1) begin
        $display("TIMEOUT: player 证据不足 exit=%b tile=%0d buzzer=%0d uart=%0d led=%0d spk=%b",
                 dut.test_exited, tile_write_count, buzzer_write_count,
                 uart_write_count, led_change_count, spk);
        $finish;
    end

    $display("PASS: Bad Apple player 从 SDRAM 解析 BAM1，并驱动 VGA/buzzer/LED/UART");
    $finish;
end

endmodule
