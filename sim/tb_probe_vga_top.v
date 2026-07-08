// probe_vga_top 的 thin-probe 仿真。
// 这里只验证最小 VGA 行为：同步脉冲会出现，active video 内存在多种颜色。
`timescale 1ns/1ps

module tb_probe_vga_top;

reg clk;
reg reset;

wire [3:0] led;
wire vga_r;
wire vga_g;
wire vga_b;
wire vga_hs;
wire vga_vs;
wire vga_mf;
wire vga_clr;
wire vga_qd;

integer red_seen;
integer green_seen;
integer blue_seen;
integer white_seen;
integer hs_edges;
integer vs_edges;

probe_vga_top #(
    .H_VISIBLE(16),
    .H_FRONT(2),
    .H_SYNC(2),
    .H_BACK(2),
    .V_VISIBLE(12),
    .V_FRONT(1),
    .V_SYNC(1),
    .V_BACK(1),
    .HEARTBEAT_TICKS(8)
) dut (
    .clk(clk),
    .reset(reset),
    .led(led),
    .vga_r(vga_r),
    .vga_g(vga_g),
    .vga_b(vga_b),
    .vga_hs(vga_hs),
    .vga_vs(vga_vs),
    .vga_mf(vga_mf),
    .vga_clr(vga_clr),
    .vga_qd(vga_qd)
);

always #5 clk = ~clk;

initial begin
    clk = 1'b0;
    reset = 1'b0;
    red_seen = 0;
    green_seen = 0;
    blue_seen = 0;
    white_seen = 0;
    hs_edges = 0;
    vs_edges = 0;

    $dumpfile("sim/build/tb_probe_vga_top.vcd");
    $dumpvars(0, tb_probe_vga_top);

    #30;
    reset = 1'b1;

    #12000;
    if (hs_edges == 0) begin
        $display("FAIL: VGA 没有产生 HS 脉冲");
        $finish;
    end
    if (vs_edges == 0) begin
        $display("FAIL: VGA 没有产生 VS 脉冲");
        $finish;
    end
    if (red_seen == 0 || green_seen == 0 || blue_seen == 0 || white_seen == 0) begin
        $display("FAIL: active video 没有覆盖预期颜色 red=%0d green=%0d blue=%0d white=%0d",
            red_seen, green_seen, blue_seen, white_seen);
        $finish;
    end
    $display("PASS: probe_vga_top 产生同步与彩条输出");
    $finish;
end

always @(negedge vga_hs) begin
    hs_edges = hs_edges + 1;
end

always @(negedge vga_vs) begin
    vs_edges = vs_edges + 1;
end

always @(posedge clk) begin
    if (dut.active_video) begin
        case ({vga_r, vga_g, vga_b})
            3'b100: red_seen = red_seen + 1;
            3'b010: green_seen = green_seen + 1;
            3'b001: blue_seen = blue_seen + 1;
            3'b111: white_seen = white_seen + 1;
            default: begin
            end
        endcase
    end
end

endmodule
