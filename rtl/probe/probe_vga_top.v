// Probe 5b：VGA thin probe。
// 只验证最小显示链路：时序、RGB 三路和若干可能相关的辅助控制脚。
// 这里故意不引入字符 RAM / SoC / MMIO，先让上板现象尽量简单。
module probe_vga_top #(
    parameter integer CLK_DIV = 2,
    parameter integer H_VISIBLE = 640,
    parameter integer H_FRONT = 16,
    parameter integer H_SYNC = 96,
    parameter integer H_BACK = 48,
    parameter integer V_VISIBLE = 480,
    parameter integer V_FRONT = 10,
    parameter integer V_SYNC = 2,
    parameter integer V_BACK = 33,
    parameter integer HEARTBEAT_TICKS = 25_000_000,
    // 下面三个控制脚在引脚文档里出现了，但当前仓库缺少更完整语义说明。
    // 先把默认值参数化，方便上板后按真实现象收敛。
    parameter VGA_MF_DEFAULT = 1'b0,
    parameter VGA_CLR_DEFAULT = 1'b1,
    parameter VGA_QD_DEFAULT = 1'b0
) (
    input clk,
    input reset,
    output reg [3:0] led,
    output reg vga_r,
    output reg vga_g,
    output reg vga_b,
    output vga_hs,
    output vga_vs,
    output vga_mf,
    output vga_clr,
    output vga_qd
);

wire rst;
wire pixel_tick;
wire [11:0] pixel_x;
wire [11:0] pixel_y;
wire active_video;
wire frame_start;
reg [31:0] heartbeat_count;

assign rst = !reset;
assign vga_mf = VGA_MF_DEFAULT;
assign vga_clr = VGA_CLR_DEFAULT;
assign vga_qd = VGA_QD_DEFAULT;

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
    .reset(rst),
    .pixel_tick(pixel_tick),
    .pixel_x(pixel_x),
    .pixel_y(pixel_y),
    .hsync(vga_hs),
    .vsync(vga_vs),
    .active_video(active_video),
    .frame_start(frame_start)
);

always @(posedge clk) begin
    if (rst) begin
        heartbeat_count <= 32'd0;
        led <= 4'b0001;
    end else if (heartbeat_count >= HEARTBEAT_TICKS - 1) begin
        heartbeat_count <= 32'd0;
        led <= {led[2:0], led[3]};
        if (led == 4'b0000) begin
            led <= 4'b0001;
        end
    end else begin
        heartbeat_count <= heartbeat_count + 32'd1;
    end
end

always @(*) begin
    vga_r = 1'b0;
    vga_g = 1'b0;
    vga_b = 1'b0;

    if (active_video) begin
        if (pixel_x < (H_VISIBLE / 4)) begin
            vga_r = 1'b1;
        end else if (pixel_x < (H_VISIBLE / 2)) begin
            vga_g = 1'b1;
        end else if (pixel_x < ((H_VISIBLE * 3) / 4)) begin
            vga_b = 1'b1;
        end else begin
            vga_r = 1'b1;
            vga_g = 1'b1;
            vga_b = 1'b1;
        end
    end
end

endmodule
