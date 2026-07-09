// M2a / sdram_data_ctrl 的板级 probe。
// 它沿用现有 SDRAM probe 的板级外壳，把固定自检脚本跑在真实 SDRAM 上，
// 用 LED 给粗状态，用 UART 给最终 PASS/FAIL 和失败细节。
module probe_sdram_data_ctrl_top #(
    parameter integer SDRAM_CLK_INVERT = 1,
    parameter integer CLK_FREQ = 50000000,
    parameter integer UART_BAUD = 9600,
    parameter integer CTRL_PWRUP_WAIT_CYCLES = 16'd10000,
    parameter integer CTRL_TRP_CYCLES = 16'd3,
    parameter integer CTRL_TRFC_CYCLES = 16'd7,
    parameter integer CTRL_TMRD_CYCLES = 16'd2,
    parameter integer CTRL_TRCD_CYCLES = 16'd3,
    parameter integer CTRL_TWR_CYCLES = 16'd3,
    parameter integer CTRL_CAS_LATENCY_CYCLES = 16'd2,
    parameter integer CTRL_REFI_CYCLES = 16'd780,
    parameter [12:0]  CTRL_MODE_REG_VALUE = 13'h220,
    parameter integer RUNNER_WAIT_TIMEOUT_CYCLES = 24'd200000,
    parameter integer RUNNER_PRESSURE_TIMEOUT_CYCLES = 24'd8192,
    parameter integer RUNNER_LOCAL_RESET_HOLD_CYCLES = 8'd4
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

wire        rst;
wire        ctrl_reset;
wire        dq_oe;
wire [15:0] dq_out;
wire [15:0] dq_in;
wire        req_valid;
wire        req_ready;
wire        req_we;
wire [31:0] req_addr;
wire [31:0] req_wdata;
wire [3:0]  req_wstrb;
wire        resp_valid;
wire [31:0] resp_rdata;
wire        resp_err;
wire [5:0]  dbg_state;
wire        dbg_refresh_pending;
wire        ctrl_local_reset;
wire [3:0]  status_led;
wire        report_valid;
wire        report_fail;
wire [7:0]  report_case_id;
wire [7:0]  report_step_id;
wire [7:0]  report_error_code;
wire [31:0] report_info;
wire [31:0] report_expected;
wire [31:0] report_actual;
wire        reporter_valid;
wire [7:0]  reporter_data;
wire        reporter_busy;
wire        uart_ready;

assign rst = !reset;
assign ctrl_reset = rst | ctrl_local_reset;
assign sh_clk = (SDRAM_CLK_INVERT != 0) ? !clk : clk;
assign dq_in = sh_db;
assign sh_db = dq_oe ? dq_out : 16'hzzzz;
assign led = status_led;

sdram_data_ctrl_probe_runner #(
    .WAIT_TIMEOUT_CYCLES(RUNNER_WAIT_TIMEOUT_CYCLES),
    .PRESSURE_TIMEOUT_CYCLES(RUNNER_PRESSURE_TIMEOUT_CYCLES),
    .LOCAL_RESET_HOLD_CYCLES(RUNNER_LOCAL_RESET_HOLD_CYCLES)
) runner (
    .clk(clk),
    .reset(rst),
    .req_valid(req_valid),
    .req_ready(req_ready),
    .req_we(req_we),
    .req_addr(req_addr),
    .req_wdata(req_wdata),
    .req_wstrb(req_wstrb),
    .resp_valid(resp_valid),
    .resp_rdata(resp_rdata),
    .resp_err(resp_err),
    .dbg_state(dbg_state),
    .sdram_cs_n(sh_ncs),
    .sdram_ras_n(sh_nras),
    .sdram_cas_n(sh_ncas),
    .sdram_we_n(sh_nwe),
    .ctrl_local_reset(ctrl_local_reset),
    .status_led(status_led),
    .report_valid(report_valid),
    .report_fail(report_fail),
    .report_case_id(report_case_id),
    .report_step_id(report_step_id),
    .report_error_code(report_error_code),
    .report_info(report_info),
    .report_expected(report_expected),
    .report_actual(report_actual)
);

sdram_data_ctrl #(
    .PWRUP_WAIT_CYCLES(CTRL_PWRUP_WAIT_CYCLES),
    .TRP_CYCLES(CTRL_TRP_CYCLES),
    .TRFC_CYCLES(CTRL_TRFC_CYCLES),
    .TMRD_CYCLES(CTRL_TMRD_CYCLES),
    .TRCD_CYCLES(CTRL_TRCD_CYCLES),
    .TWR_CYCLES(CTRL_TWR_CYCLES),
    .CAS_LATENCY_CYCLES(CTRL_CAS_LATENCY_CYCLES),
    .REFI_CYCLES(CTRL_REFI_CYCLES),
    .MODE_REG_VALUE(CTRL_MODE_REG_VALUE)
) ctrl (
    .clk(clk),
    .reset(ctrl_reset),
    .req_valid(req_valid),
    .req_ready(req_ready),
    .req_we(req_we),
    .req_addr(req_addr),
    .req_wdata(req_wdata),
    .req_wstrb(req_wstrb),
    .resp_valid(resp_valid),
    .resp_rdata(resp_rdata),
    .resp_err(resp_err),
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
    .dbg_state(dbg_state),
    .dbg_refresh_pending(dbg_refresh_pending)
);

sdram_data_ctrl_probe_reporter reporter (
    .clk(clk),
    .reset(rst),
    .report_valid(report_valid),
    .report_fail(report_fail),
    .report_case_id(report_case_id),
    .report_step_id(report_step_id),
    .report_error_code(report_error_code),
    .report_info(report_info),
    .report_expected(report_expected),
    .report_actual(report_actual),
    .tx_ready(uart_ready),
    .tx_valid(reporter_valid),
    .tx_data(reporter_data),
    .busy(reporter_busy)
);

uart_tx #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD(UART_BAUD)
) u_uart_tx (
    .clk(clk),
    .reset(rst),
    .valid(reporter_valid),
    .data_in(reporter_data),
    .ready(uart_ready),
    .txd(uart_txd)
);

wire unused_uart_rxd;
wire [3:0] unused_key;
wire unused_reporter_busy;
wire unused_dbg_refresh_pending;
assign unused_uart_rxd = uart_rxd;
assign unused_key = key;
assign unused_reporter_busy = reporter_busy;
assign unused_dbg_refresh_pending = dbg_refresh_pending;

endmodule
