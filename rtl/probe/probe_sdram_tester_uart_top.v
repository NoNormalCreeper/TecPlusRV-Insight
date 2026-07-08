// Probe 4 debug 顶层：SDRAM standalone tester + UART 结果输出 + KEY1 可控注错。
// 板载 KEY1 对应 RTL 的 key[0]，按下为低；按住 KEY1 再释放 reset，
// 会在固定地址/pattern 读回时翻转 1 bit，
// 用来板级验证 error_count 和 first_error_* 是否被锁存并经 UART 输出。
module probe_sdram_tester_uart_top #(
    parameter integer SDRAM_CLK_INVERT = 1,
    parameter integer UART_BAUD = 9600,
    parameter [9:0]  INJECT_INDEX = 10'd3,
    parameter [7:0]  INJECT_PATTERN = 8'd2
) (
    input         clk,
    input         reset,
    input  [3:0]  key,
    input         uart_rxd,
    output        uart_txd,
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
wire [15:0] dq_in_to_ctrl;
wire [9:0]  test_index;
wire [7:0]  pattern_index;
wire [7:0]  pass_count;
wire [15:0] error_count;
wire [9:0]  first_error_index;
wire [7:0]  first_error_pattern;
wire [15:0] first_error_expected;
wire [15:0] first_error_actual;
wire        done_pass;
wire        done_fail;
wire        rst;
wire        inject_enable;
wire        inject_hit;
wire        report_valid;
wire        report_fail;
wire        reporter_valid;
wire [7:0]  reporter_data;
wire        reporter_busy;
wire        uart_ready;

reg         done_pass_d;
reg         done_fail_d;

assign sh_clk = (SDRAM_CLK_INVERT != 0) ? !clk : clk;
assign dq_in = sh_db;
assign sh_db = dq_oe ? dq_out : 16'hzzzz;
assign rst = !reset;

// KEY 默认为高，按下为低。按住板载 KEY1，也就是 key[0]，可开启受控注错。
assign inject_enable = !key[0];
assign inject_hit = inject_enable &&
                    (test_index == INJECT_INDEX) &&
                    (pattern_index == INJECT_PATTERN);
assign dq_in_to_ctrl = inject_hit ? (dq_in ^ 16'h0001) : dq_in;

assign report_valid = (done_pass && !done_pass_d) || (done_fail && !done_fail_d);
assign report_fail = done_fail;

sdram_tester_ctrl ctrl (
    .clk(clk),
    .reset(rst),
    .dq_in(dq_in_to_ctrl),
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
    .pattern_index(pattern_index),
    .pass_count(pass_count),
    .error_count(error_count),
    .first_error_index(first_error_index),
    .first_error_pattern(first_error_pattern),
    .first_error_expected(first_error_expected),
    .first_error_actual(first_error_actual),
    .done_pass(done_pass),
    .done_fail(done_fail)
);

sdram_tester_uart_reporter reporter (
    .clk(clk),
    .reset(rst),
    .report_valid(report_valid),
    .report_fail(report_fail),
    .error_count(error_count),
    .first_error_index(first_error_index),
    .first_error_pattern(first_error_pattern),
    .first_error_expected(first_error_expected),
    .first_error_actual(first_error_actual),
    .tx_ready(uart_ready),
    .tx_valid(reporter_valid),
    .tx_data(reporter_data),
    .busy(reporter_busy)
);

uart_tx #(
    .CLK_FREQ(50000000),
    .BAUD(UART_BAUD)
) u_uart_tx (
    .clk(clk),
    .reset(rst),
    .valid(reporter_valid),
    .data_in(reporter_data),
    .ready(uart_ready),
    .txd(uart_txd)
);

always @(posedge clk) begin
    if (rst) begin
        done_pass_d <= 1'b0;
        done_fail_d <= 1'b0;
    end else begin
        done_pass_d <= done_pass;
        done_fail_d <= done_fail;
    end
end

wire unused_uart_rxd;
wire [2:0] unused_key;
wire unused_reporter_busy;
assign unused_uart_rxd = uart_rxd;
assign unused_key = key[3:1];
assign unused_reporter_busy = reporter_busy;

endmodule
