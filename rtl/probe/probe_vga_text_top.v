// Probe 5：字符型 VGA 显示骨架的直接上板入口。
// 当前仍然不接 SoC，只是给后续“VGA 输出字符”这条线一个可独立观察的起点。
module probe_vga_text_top #(
    parameter integer HEARTBEAT_TICKS = 25_000_000,
    parameter VGA_MF_DEFAULT = 1'b0,
    parameter VGA_CLR_DEFAULT = 1'b1,
    parameter VGA_QD_DEFAULT = 1'b0
) (
    input clk,
    input reset,
    output reg [3:0] led,
    output vga_r,
    output vga_g,
    output vga_b,
    output vga_hs,
    output vga_vs,
    output vga_mf,
    output vga_clr,
    output vga_qd
);

wire rst;
reg [31:0] heartbeat_count;

assign rst = !reset;
assign vga_mf = VGA_MF_DEFAULT;
assign vga_clr = VGA_CLR_DEFAULT;
assign vga_qd = VGA_QD_DEFAULT;

vga_text_mode text_mode (
    .clk(clk),
    .reset(rst),
    .cell_we(1'b0),
    .cell_x(6'd0),
    .cell_y(5'd0),
    .cell_char(8'h20),
    .vga_r(vga_r),
    .vga_g(vga_g),
    .vga_b(vga_b),
    .vga_hs(vga_hs),
    .vga_vs(vga_vs)
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

endmodule
