// 完整版 BAM2 的短时端到端回归：SDRAM -> FreeRTOS -> bitmap/buzzer/UART/LED。
`timescale 1ns/1ps

module tb_bad_apple_full #(
    parameter integer CPU_IMPL = 1,
    parameter FIRMWARE_MEM_FILE = "firmware/build/freertos/bad_apple_full/firmware.mem",
    parameter ASSET_MEM_FILE = "sim/build/bad_apple_full.mem"
);

reg clk;
reg reset;
wire [3:0] led;
wire [11:0] tl;
wire spk;
wire uart_txd;
wire vga_r, vga_g, vga_b, vga_hs, vga_vs;
wire sh_clk, sh_cke, sh_ncs, sh_nwe, sh_ncas, sh_nras;
wire [1:0] sh_dqm, sh_ba;
wire [12:0] sh_a;
wire [15:0] sh_db;
wire [31:0] model_read_command_count;
wire [31:0] model_write_command_count;

reg [31:0] asset_words [0:218];
integer asset_word_count;
integer i;
integer cycles;
integer bitmap_write_count;
integer buzzer_write_count;
integer uart_write_count;
reg spk_toggled;
reg previous_spk;

tecplus_minisoc_top #(
    .CLK_FREQ(4000000),
    .UART_BAUD(400000),
    .CPU_IMPL(CPU_IMPL),
    .BRAM_ADDR_WIDTH(14),
    .VGA_BITMAP_ENABLE(1),
    .VGA_TEXT_ENABLE(0),
    .BRAM_INIT_FILE(FIRMWARE_MEM_FILE)
) dut (
    .clk(clk), .reset(reset), .key(4'b1111), .led(led),
    .uart_rxd(1'b1), .uart_txd(uart_txd), .tl(tl), .spk(spk),
    .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
    .vga_hs(vga_hs), .vga_vs(vga_vs),
    .sh_clk(sh_clk), .sh_cke(sh_cke), .sh_ncs(sh_ncs), .sh_nwe(sh_nwe),
    .sh_ncas(sh_ncas), .sh_nras(sh_nras), .sh_dqm(sh_dqm),
    .sh_ba(sh_ba), .sh_a(sh_a), .sh_db(sh_db)
);

// 一帧约 20000 clocks；仍比真实板快约 42 倍，但允许 CPU 完成首帧 96-word SDRAM diff。
defparam dut.g_vga_bitmap.u_vga_bitmap.CLK_DIV = 1;
defparam dut.g_vga_bitmap.u_vga_bitmap.H_VISIBLE = 16;
defparam dut.g_vga_bitmap.u_vga_bitmap.H_FRONT = 1;
defparam dut.g_vga_bitmap.u_vga_bitmap.H_SYNC = 2;
defparam dut.g_vga_bitmap.u_vga_bitmap.H_BACK = 1;
defparam dut.g_vga_bitmap.u_vga_bitmap.V_VISIBLE = 16;
defparam dut.g_vga_bitmap.u_vga_bitmap.V_FRONT = 1;
defparam dut.g_vga_bitmap.u_vga_bitmap.V_SYNC = 1;
defparam dut.g_vga_bitmap.u_vga_bitmap.V_BACK = 982;

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
        if (dut.vga_bitmap_write)
            bitmap_write_count = bitmap_write_count + 1;
        if (dut.buzzer_ctrl_write || dut.buzzer_period_write)
            buzzer_write_count = buzzer_write_count + 1;
        if (dut.uart_fire)
            uart_write_count = uart_write_count + 1;
        if (spk != previous_spk)
            spk_toggled = 1'b1;
        previous_spk = spk;
    end
end

initial begin
    clk = 1'b0;
    reset = 1'b0;
    cycles = 0;
    bitmap_write_count = 0;
    buzzer_write_count = 0;
    uart_write_count = 0;
    spk_toggled = 1'b0;
    previous_spk = 1'b0;

    $readmemh(ASSET_MEM_FILE, asset_words);
    #2;
    asset_word_count = asset_words[2] / 4;
    for (i = 0; i < asset_word_count; i = i + 1) begin
        model.mem[model_key(32'h8100_0000 + i * 4)] = asset_words[i][15:0];
        model.mem[model_key(32'h8100_0002 + i * 4)] = asset_words[i][31:16];
    end
    repeat (5) @(posedge clk);
    reset = 1'b1;

    while (cycles < 2500000 && !dut.test_exited) begin
        @(posedge clk);
        cycles = cycles + 1;
    end
    if (!dut.test_exited) begin
        $display("TIMEOUT: BAM2 FreeRTOS player 未完成");
        $finish;
    end
    if (dut.test_exit_code !== 32'h1 || led !== 4'h5) begin
        $display("FAIL: exit=0x%08x led=0x%x", dut.test_exit_code, led);
        $finish;
    end
    if (bitmap_write_count !== 99) begin
        $display("FAIL: bitmap writes 应为 99，实际 %0d", bitmap_write_count);
        $finish;
    end
    if (dut.g_vga_bitmap.u_vga_bitmap.framebuffer[0] !== 32'h0000_0000 ||
        dut.g_vga_bitmap.u_vga_bitmap.framebuffer[1] !== 32'h8000_0001 ||
        dut.g_vga_bitmap.u_vga_bitmap.framebuffer[95] !== 32'hffff_ffff) begin
        $display("FAIL: BAM2 最终 framebuffer 内容不匹配");
        $finish;
    end
    if (buzzer_write_count < 5 || !spk_toggled || uart_write_count < 10) begin
        $display("FAIL: 外设证据不足 buzzer=%0d spk=%b uart=%0d",
                 buzzer_write_count, spk_toggled, uart_write_count);
        $finish;
    end
    if (model_read_command_count == 0 || model_write_command_count != 0) begin
        $display("FAIL: SDRAM traffic 异常 read=%0d write=%0d",
                 model_read_command_count, model_write_command_count);
        $finish;
    end
    $display("PASS: FreeRTOS 从 SDRAM 播放 BAM2 bitmap 与 MIDI 音频");
    $finish;
end

endmodule
