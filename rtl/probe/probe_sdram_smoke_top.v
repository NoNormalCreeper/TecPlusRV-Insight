// Probe 4a 顶层：把 SDRAM smoke 控制器接到 TEC-PLUS 板级端口。
// 顶层主要负责 reset 极性、SDRAM 时钟直通、以及 DQ 双向总线的三态控制。
module probe_sdram_smoke_top (
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
wire        done_pass;
wire        done_fail;
wire        rst;

assign sh_clk = clk;
assign dq_in = sh_db;
// SDRAM DQ 是 inout：写时 FPGA 驱动，读/空闲时输出高阻，避免和 SDRAM 对打。
assign sh_db = dq_oe ? dq_out : 16'hzzzz;
// 核心板 RESET 实测为低有效，top 内部统一转换为高有效 rst。
assign rst = !reset;

sdram_smoke_ctrl ctrl (
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
    .done_pass(done_pass),
    .done_fail(done_fail)
);

endmodule
