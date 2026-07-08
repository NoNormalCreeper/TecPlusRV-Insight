// 最小 VGA timing 发生器。
// 默认按 TEC-PLUS 50MHz 板时钟输入，内部用像素时钟使能实现 25MHz 级扫描。
// 这里故意只做最薄的一层：给 probe / text-mode 共用时序，不掺杂字符或图形逻辑。
module vga_timing_640x480 #(
    parameter integer CLK_DIV = 2,
    parameter integer H_VISIBLE = 640,
    parameter integer H_FRONT = 16,
    parameter integer H_SYNC = 96,
    parameter integer H_BACK = 48,
    parameter integer V_VISIBLE = 480,
    parameter integer V_FRONT = 10,
    parameter integer V_SYNC = 2,
    parameter integer V_BACK = 33
) (
    input clk,
    input reset,
    output reg pixel_tick,
    output reg [11:0] pixel_x,
    output reg [11:0] pixel_y,
    output reg hsync,
    output reg vsync,
    output reg active_video,
    output reg frame_start
);

localparam integer H_TOTAL = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;
localparam integer V_TOTAL = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;

reg [7:0] div_count;

always @(posedge clk) begin
    if (reset) begin
        div_count <= 8'd0;
        pixel_tick <= 1'b0;
    end else if (div_count >= CLK_DIV - 1) begin
        div_count <= 8'd0;
        pixel_tick <= 1'b1;
    end else begin
        div_count <= div_count + 8'd1;
        pixel_tick <= 1'b0;
    end
end

always @(posedge clk) begin
    if (reset) begin
        pixel_x <= 12'd0;
        pixel_y <= 12'd0;
        frame_start <= 1'b0;
    end else if (pixel_tick) begin
        frame_start <= 1'b0;
        if (pixel_x >= H_TOTAL - 1) begin
            pixel_x <= 12'd0;
            if (pixel_y >= V_TOTAL - 1) begin
                pixel_y <= 12'd0;
                frame_start <= 1'b1;
            end else begin
                pixel_y <= pixel_y + 12'd1;
            end
        end else begin
            pixel_x <= pixel_x + 12'd1;
        end
    end else begin
        frame_start <= 1'b0;
    end
end

always @(*) begin
    active_video = (pixel_x < H_VISIBLE) && (pixel_y < V_VISIBLE);
    hsync = !((pixel_x >= H_VISIBLE + H_FRONT) &&
              (pixel_x < H_VISIBLE + H_FRONT + H_SYNC));
    vsync = !((pixel_y >= V_VISIBLE + V_FRONT) &&
              (pixel_y < V_VISIBLE + V_FRONT + V_SYNC));
end

endmodule
