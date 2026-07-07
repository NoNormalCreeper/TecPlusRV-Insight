// Probe 4 顶层：把独立 SDRAM tester 接到 TEC-PLUS U2 SDRAM 与 LED。
module probe_sdram_tester_top #(
    // SDRAM 在自己的时钟沿采样命令/地址/数据。反相输出能给 FPGA 寄存器输出半个周期建立时间。
    parameter integer SDRAM_CLK_INVERT = 1
) (
    input         clk,
    input         reset,
    output [3:0]  led,
    output        sh_clk,
    output        sh_cke,
    output        sh_ncs,
    output        sh_nwe,
    output        sh_ncas,
    output        sh_nras,
    output [1:0]  sh_dqm,
    output [1:0]  sh_ba,
    output [12:0] sh_a,
    inout  [15:0] sh_db
);

wire        dq_oe;
wire [15:0] dq_out;
wire [15:0] dq_in;
wire [9:0]  test_index;
wire [7:0]  pass_count;
wire        done_pass;
wire        done_fail;
wire        rst;

assign sh_clk = (SDRAM_CLK_INVERT != 0) ? !clk : clk;
assign dq_in = sh_db;
assign sh_db = dq_oe ? dq_out : 16'hzzzz;
assign rst = !reset;

sdram_tester_ctrl ctrl (
    .clk(clk),
    .reset(rst),
    .dq_in(dq_in),
    .dq_oe(dq_oe),
    .dq_out(dq_out),
    .sdram_cke(sh_cke),
    .sdram_cs_n(sh_ncs),
    .sdram_ras_n(sh_nras),
    .sdram_cas_n(sh_ncas),
    .sdram_we_n(sh_nwe),
    .sdram_ba(sh_ba),
    .sdram_addr(sh_a),
    .sdram_dqm(sh_dqm),
    .status_led(led),
    .test_index(test_index),
    .pass_count(pass_count),
    .done_pass(done_pass),
    .done_fail(done_fail)
);

endmodule
