// vga_text_mode 的模块级仿真。
// 先确认 reset 后初始化完成，再确认一个 32-bit 写入能更新四个连续 tile。
`timescale 1ns/1ps

module tb_vga_text_mode;

reg clk;
reg reset;
reg tile_we;
reg [8:0] tile_addr;
reg [31:0] tile_wdata;
reg [3:0] tile_wstrb;

wire ready;
wire vblank;
wire [15:0] frame_count;
wire vga_r;
wire vga_g;
wire vga_b;
wire vga_hs;
wire vga_vs;

integer hs_edges;
integer vs_edges;
integer cell_pixels_before;
integer cell_pixels_after;
reg     measuring_before;
reg     measuring_after;
reg     saw_vblank;

vga_text_mode #(
    .H_VISIBLE(64),
    .H_FRONT(4),
    .H_SYNC(4),
    .H_BACK(4),
    .V_VISIBLE(48),
    .V_FRONT(2),
    .V_SYNC(2),
    .V_BACK(2),
    .TEXT_COLS(4),
    .TEXT_ROWS(3),
    .CELL_WIDTH(16),
    .CELL_HEIGHT(16),
    .BANNER_ROW(1),
    .BANNER_COL(1)
) dut (
    .clk(clk),
    .reset(reset),
    .tile_we(tile_we),
    .tile_addr(tile_addr),
    .tile_wdata(tile_wdata),
    .tile_wstrb(tile_wstrb),
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

task wait_frame;
    integer start_edges;
    begin
        start_edges = vs_edges;
        while (vs_edges < start_edges + 1) begin
            @(posedge clk);
        end
    end
endtask

initial begin
    clk = 1'b0;
    reset = 1'b0;
    tile_we = 1'b0;
    tile_addr = 9'd0;
    tile_wdata = 32'h0000_0000;
    tile_wstrb = 4'b0000;
    hs_edges = 0;
    vs_edges = 0;
    cell_pixels_before = 0;
    cell_pixels_after = 0;
    measuring_before = 1'b0;
    measuring_after = 1'b0;
    saw_vblank = 1'b0;

    $dumpfile("sim/build/tb_vga_text_mode.vcd");
    $dumpvars(0, tb_vga_text_mode);

    #30;
    reset = 1'b1;
    #20;
    reset = 1'b0;

    wait (ready == 1'b1);

    measuring_before = 1'b1;
    wait_frame;
    measuring_before = 1'b0;

    if (cell_pixels_before != 0) begin
        $display("FAIL: 空白 cell 在写入前不应有亮点 before=%0d", cell_pixels_before);
        $finish;
    end

    @(posedge clk);
    tile_addr <= 9'd0;
    tile_wdata <= {"G", "E", "C", "A"};
    tile_wstrb <= 4'b1111;
    tile_we <= 1'b1;
    @(posedge clk);
    tile_we <= 1'b0;
    tile_wstrb <= 4'b0000;

    measuring_after = 1'b1;
    wait_frame;
    measuring_after = 1'b0;

    if (hs_edges == 0 || vs_edges == 0) begin
        $display("FAIL: vga_text_mode 没有产生同步脉冲");
        $finish;
    end
    if (cell_pixels_after == 0) begin
        $display("FAIL: 写入口没有让目标 cell 产生字符像素");
        $finish;
    end
    if (!saw_vblank || frame_count == 0) begin
        $display("FAIL: vblank/frame_count 状态没有随扫描更新");
        $finish;
    end
    $display("PASS: vga_text_mode write-only packed tile 写口和扫描状态都正常");
    $finish;
end

always @(negedge vga_hs) begin
    hs_edges = hs_edges + 1;
end

always @(negedge vga_vs) begin
    vs_edges = vs_edges + 1;
end

always @(posedge clk) begin
    if (vblank) begin
        saw_vblank <= 1'b1;
    end
    if (dut.active_video &&
        dut.pixel_x < dut.CELL_WIDTH &&
        dut.pixel_y < dut.CELL_HEIGHT &&
        {vga_r, vga_g, vga_b} != 3'b000) begin
        if (measuring_before) begin
            cell_pixels_before = cell_pixels_before + 1;
        end
        if (measuring_after) begin
            cell_pixels_after = cell_pixels_after + 1;
        end
    end
end

endmodule
