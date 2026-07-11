// 64x48 1bpp VGA framebuffer 的模块级回归。
`timescale 1ns/1ps

module tb_vga_bitmap_1bpp;

reg clk;
reg reset;
reg fb_we;
reg [6:0] fb_addr;
reg [31:0] fb_wdata;

wire ready;
wire vblank;
wire [15:0] frame_count;
wire vga_r;
wire vga_g;
wire vga_b;
wire vga_hs;
wire vga_vs;

vga_bitmap_1bpp #(
    .CLK_DIV(1)
) dut (
    .clk(clk),
    .reset(reset),
    .fb_we(fb_we),
    .fb_addr(fb_addr),
    .fb_wdata(fb_wdata),
    .ready(ready),
    .vblank(vblank),
    .frame_count(frame_count),
    .vga_r(vga_r),
    .vga_g(vga_g),
    .vga_b(vga_b),
    .vga_hs(vga_hs),
    .vga_vs(vga_vs)
);

always #5 clk = ~clk;

task write_word;
    input [6:0] addr;
    input [31:0] value;
    begin
        @(negedge clk);
        fb_addr = addr;
        fb_wdata = value;
        fb_we = 1'b1;
        @(negedge clk);
        fb_we = 1'b0;
    end
endtask

task wait_pixel;
    input [11:0] x;
    input [11:0] y;
    begin
        while (dut.pixel_x !== x || dut.pixel_y !== y) begin
            // timing counter 在 posedge 用 nonblocking assignment 更新；在 negedge 采样
            // 避免刚命中目标坐标就前进一个像素的 testbench race。
            @(negedge clk);
        end
        #1;
    end
endtask

initial begin
    clk = 1'b0;
    reset = 1'b1;
    fb_we = 1'b0;
    fb_addr = 7'd0;
    fb_wdata = 32'd0;

    repeat (4) @(posedge clk);
    reset = 1'b0;
    wait (ready === 1'b1);

    if (dut.framebuffer[0] !== 32'd0 || dut.framebuffer[95] !== 32'd0) begin
        $display("FAIL: 1bpp framebuffer 上电清零失败");
        $finish;
    end

    // 左上逻辑像素与右下逻辑像素置白。
    write_word(7'd0, 32'h0000_0001);
    write_word(7'd95, 32'h8000_0000);

    // 越界写必须被忽略。
    write_word(7'd96, 32'hffff_ffff);
    if (dut.framebuffer[95] !== 32'h8000_0000) begin
        $display("FAIL: framebuffer 越界写破坏末 word");
        $finish;
    end

    wait_pixel(12'd63, 12'd48);
    if (vga_r || vga_g || vga_b) begin
        $display("FAIL: 左黑边出现白点 x=%0d y=%0d in_bitmap=%0d word=%0d bit=%0d pixel=%0d",
            dut.pixel_x, dut.pixel_y, dut.in_bitmap,
            dut.scan_word_addr, dut.scan_bit_addr, dut.scan_pixel);
        $finish;
    end

    wait_pixel(12'd64, 12'd48);
    if (!(vga_r && vga_g && vga_b)) begin
        $display("FAIL: word 0 bit 0 未映射到左上逻辑像素");
        $finish;
    end

    wait_pixel(12'd71, 12'd55);
    if (!(vga_r && vga_g && vga_b)) begin
        $display("FAIL: 左上逻辑像素未按 8x8 放大");
        $finish;
    end

    wait_pixel(12'd72, 12'd48);
    if (vga_r || vga_g || vga_b) begin
        $display("FAIL: 相邻黑像素被错误点亮");
        $finish;
    end

    wait_pixel(12'd568, 12'd424);
    if (!(vga_r && vga_g && vga_b)) begin
        $display("FAIL: word 95 bit 31 未映射到右下逻辑像素");
        $finish;
    end

    wait_pixel(12'd576, 12'd424);
    if (vga_r || vga_g || vga_b) begin
        $display("FAIL: 右黑边出现白点");
        $finish;
    end

    wait_pixel(12'd0, 12'd480);
    if (!vblank) begin
        $display("FAIL: 垂直消隐状态未拉高");
        $finish;
    end

    wait (frame_count >= 16'd1);
    $display("PASS: vga_bitmap_1bpp 清零、边界、寻址和扫描行为正确");
    $finish;
end

endmodule
