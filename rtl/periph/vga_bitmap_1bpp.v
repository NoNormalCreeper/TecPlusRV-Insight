// 64x48 1bpp VGA framebuffer。
//
// framebuffer 固定为 96 个 32-bit word，CPU 只做完整 word 写；扫描端异步读取，
// 目标是在 Spartan-6 上推断为 distributed RAM，不占用已经满载的 RAMB16。
// 真实资源类型和 50 MHz slack 仍必须以 ISE 14.7 Map/PAR 报告为准。
module vga_bitmap_1bpp #(
    parameter integer CLK_DIV = 2,
    parameter integer H_VISIBLE = 640,
    parameter integer H_FRONT = 16,
    parameter integer H_SYNC = 96,
    parameter integer H_BACK = 48,
    parameter integer V_VISIBLE = 480,
    parameter integer V_FRONT = 10,
    parameter integer V_SYNC = 2,
    parameter integer V_BACK = 33,
    parameter integer SCALE_SHIFT = 3,
    parameter integer X_OFFSET = 64,
    parameter integer Y_OFFSET = 48
) (
    input clk,
    input reset,
    input fb_we,
    input [6:0] fb_addr,
    input [31:0] fb_wdata,
    output reg ready,
    output vblank,
    output reg [15:0] frame_count,
    output reg vga_r,
    output reg vga_g,
    output reg vga_b,
    output vga_hs,
    output vga_vs
);

localparam integer LOGICAL_WIDTH = 64;
localparam integer LOGICAL_HEIGHT = 48;
localparam integer FRAMEBUFFER_WORDS = 96;
localparam integer DISPLAY_WIDTH = LOGICAL_WIDTH << SCALE_SHIFT;
localparam integer DISPLAY_HEIGHT = LOGICAL_HEIGHT << SCALE_SHIFT;

(* ram_style = "distributed" *)
reg [31:0] framebuffer [0:FRAMEBUFFER_WORDS-1];
reg [6:0] clear_index;

wire pixel_tick;
wire [11:0] pixel_x;
wire [11:0] pixel_y;
wire active_video;
wire frame_start;
wire hsync;
wire vsync;

wire in_bitmap = active_video &&
    (pixel_x >= X_OFFSET) && (pixel_x < X_OFFSET + DISPLAY_WIDTH) &&
    (pixel_y >= Y_OFFSET) && (pixel_y < Y_OFFSET + DISPLAY_HEIGHT);
wire [11:0] local_x = pixel_x - X_OFFSET;
wire [11:0] local_y = pixel_y - Y_OFFSET;
wire [5:0] logical_x = local_x >> SCALE_SHIFT;
wire [5:0] logical_y = local_y >> SCALE_SHIFT;
wire [6:0] bitmap_word_addr = {logical_y, 1'b0} + logical_x[5];
wire [6:0] scan_word_addr = in_bitmap ? bitmap_word_addr : 7'd0;
wire [4:0] scan_bit_addr = in_bitmap ? logical_x[4:0] : 5'd0;
// 保持 XST 的 distributed RAM inference 模板：同步写、整 word 异步读。
// 不要把 memory address 与 bit address 合成连续动态索引，否则 XST 14.7
// 可能把整个 framebuffer 展开成 FF 和组合 mux。
wire ram_write = !ready || (fb_we && fb_addr < FRAMEBUFFER_WORDS);
wire [6:0] ram_write_addr = ready ? fb_addr : clear_index;
wire [31:0] ram_write_data = ready ? fb_wdata : 32'd0;
wire [31:0] scan_word = framebuffer[scan_word_addr];
wire scan_pixel = scan_word[scan_bit_addr];

vga_timing_640x480 #(
    .CLK_DIV(CLK_DIV),
    .H_VISIBLE(H_VISIBLE),
    .H_FRONT(H_FRONT),
    .H_SYNC(H_SYNC),
    .H_BACK(H_BACK),
    .V_VISIBLE(V_VISIBLE),
    .V_FRONT(V_FRONT),
    .V_SYNC(V_SYNC),
    .V_BACK(V_BACK)
) timing (
    .clk(clk),
    .reset(reset),
    .pixel_tick(pixel_tick),
    .pixel_x(pixel_x),
    .pixel_y(pixel_y),
    .hsync(hsync),
    .vsync(vsync),
    .active_video(active_video),
    .frame_start(frame_start)
);

assign vga_hs = hsync;
assign vga_vs = vsync;
assign vblank = (pixel_y >= V_VISIBLE);

always @(posedge clk) begin
    if (ram_write)
        framebuffer[ram_write_addr] <= ram_write_data;
end

always @(posedge clk) begin
    if (reset) begin
        clear_index <= 7'd0;
        ready <= 1'b0;
        frame_count <= 16'd0;
    end else begin
        if (frame_start) begin
            frame_count <= frame_count + 1'b1;
        end

        if (!ready) begin
            if (clear_index == FRAMEBUFFER_WORDS - 1) begin
                clear_index <= 7'd0;
                ready <= 1'b1;
            end else begin
                clear_index <= clear_index + 1'b1;
            end
        end
    end
end

always @(*) begin
    if (ready && in_bitmap && scan_pixel) begin
        vga_r = 1'b1;
        vga_g = 1'b1;
        vga_b = 1'b1;
    end else begin
        vga_r = 1'b0;
        vga_g = 1'b0;
        vga_b = 1'b0;
    end
end

endmodule
