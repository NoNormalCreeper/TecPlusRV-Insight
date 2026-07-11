// DarkRISCV 经 TinyBus 写入 64x48 1bpp framebuffer 的 SoC 级回归。
`timescale 1ns/1ps

module tb_minisoc_vga_bitmap #(
    parameter integer CPU_IMPL = 1,
    parameter FIRMWARE_MEM_FILE = "firmware/build/firmware.mem",
    parameter integer TIMEOUT_CYCLES = 4000000
);

reg clk;
reg reset;
integer fb_write_count;

wire [3:0] led;
wire [11:0] tl;
wire spk;
wire uart_txd;
wire vga_r;
wire vga_g;
wire vga_b;
wire vga_hs;
wire vga_vs;

tecplus_minisoc_top #(
    .CLK_FREQ(1000000),
    .UART_BAUD(100000),
    .CPU_IMPL(CPU_IMPL),
    .BRAM_ADDR_WIDTH(14),
    .VGA_BITMAP_ENABLE(1),
    .BRAM_INIT_FILE(FIRMWARE_MEM_FILE)
) dut (
    .clk(clk),
    .reset(reset),
    .key(4'b1111),
    .led(led),
    .uart_rxd(1'b1),
    .uart_txd(uart_txd),
    .tl(tl),
    .spk(spk),
    .vga_r(vga_r),
    .vga_g(vga_g),
    .vga_b(vga_b),
    .vga_hs(vga_hs),
    .vga_vs(vga_vs)
);

always #5 clk = ~clk;

initial begin
    clk = 1'b0;
    reset = 1'b0;
    fb_write_count = 0;
    repeat (5) @(posedge clk);
    reset = 1'b1;
end

initial begin
    repeat (TIMEOUT_CYCLES) begin
        @(posedge clk);
        if (dut.vga_bitmap_write)
            fb_write_count = fb_write_count + 1;

        if (dut.test_exited) begin
            if (dut.test_exit_code !== 32'h0000_0001) begin
                $display("FAIL: VGA bitmap firmware test_exit=0x%08x", dut.test_exit_code);
                $finish;
            end
            if (fb_write_count !== 96) begin
                $display("FAIL: framebuffer 应写 96 个 word，实际为 %0d", fb_write_count);
                $finish;
            end
            if (dut.g_vga_bitmap.u_vga_bitmap.framebuffer[0] !== 32'hffff_ffff ||
                dut.g_vga_bitmap.u_vga_bitmap.framebuffer[2] !== 32'h8000_0001 ||
                dut.g_vga_bitmap.u_vga_bitmap.framebuffer[48] !== 32'hffff_ffff ||
                dut.g_vga_bitmap.u_vga_bitmap.framebuffer[95] !== 32'hffff_ffff) begin
                $display("FAIL: framebuffer 静态图样内容不符合预期");
                $finish;
            end
            if (led !== 4'h5) begin
                $display("FAIL: firmware 未报告通过，led=0x%0x", led);
                $finish;
            end
            $display("PASS: DarkRISCV 经 VGA MMIO 写入完整 64x48 1bpp 图样");
            $finish;
        end
    end

    $display("TIMEOUT: VGA bitmap firmware 未完成");
    $finish;
end

endmodule
