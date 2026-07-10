// M2a 板级 probe 的自检 runner。
// 它不模拟 SDRAM，本质上是固定脚本的 host driver：
// 按顺序驱动 sdram_data_ctrl，覆盖全字写读、部分写、bank/row/A12、
// misaligned 错误、持续压力下 refresh、以及事务中途 local reset 后恢复。
module sdram_data_ctrl_probe_runner #(
    parameter integer WAIT_TIMEOUT_CYCLES = 24'd200000,
    parameter integer PRESSURE_TIMEOUT_CYCLES = 24'd8192,
    parameter integer LOCAL_RESET_HOLD_CYCLES = 8'd4
) (
    input         clk,
    input         reset,
    output reg    req_valid,
    input         req_ready,
    output reg    req_we,
    output reg [31:0] req_addr,
    output reg [31:0] req_wdata,
    output reg [3:0]  req_wstrb,
    input         resp_valid,
    input  [31:0] resp_rdata,
    input         resp_err,
    input  [5:0]  dbg_state,
    input         sdram_cs_n,
    input         sdram_ras_n,
    input         sdram_cas_n,
    input         sdram_we_n,
    output reg    ctrl_local_reset,
    output reg [3:0] status_led,
    output reg    report_valid,
    output reg    report_fail,
    output reg [7:0] report_case_id,
    output reg [7:0] report_step_id,
    output reg [7:0] report_error_code,
    output reg [31:0] report_info,
    output reg [31:0] report_expected,
    output reg [31:0] report_actual
);

localparam [6:0]
    ST_WAIT_INIT               = 7'd0,
    ST_PREP_CASE1_WRITE        = 7'd1,
    ST_PREP_CASE1_READ         = 7'd2,
    ST_PREP_CASE2_WRITE        = 7'd3,
    ST_PREP_CASE2_READ         = 7'd4,
    ST_PREP_CASE3_WRITE        = 7'd5,
    ST_PREP_CASE3_READ         = 7'd6,
    ST_PREP_CASE4_READ         = 7'd7,
    ST_PREP_CASE5_WRITE        = 7'd8,
    ST_CASE6_PRESSURE_SETUP    = 7'd9,
    ST_CASE6_PRESSURE_RUN      = 7'd10,
    ST_CASE6_PRESSURE_DRAIN    = 7'd11,
    ST_CASE7_PRIME_WAIT_READY  = 7'd12,
    ST_CASE7_PRIME_WAIT_ACCEPT = 7'd13,
    ST_CASE7_WAIT_WRITE_STAGE  = 7'd14,
    ST_CASE7_ASSERT_RESET      = 7'd15,
    ST_CASE7_WAIT_POR_STATE    = 7'd16,
    ST_CASE7_WAIT_CTRL_READY   = 7'd17,
    ST_PREP_CASE7_WRITE        = 7'd18,
    ST_PREP_CASE7_READ         = 7'd19,
    ST_OP_WAIT_READY           = 7'd20,
    ST_OP_WAIT_ACCEPT          = 7'd21,
    ST_OP_WAIT_RESP            = 7'd22,
    ST_PREP_CASE3_WRITE_HIGH   = 7'd23,
    ST_PREP_CASE3_READ_HIGH    = 7'd24,
    ST_PASS                    = 7'd62,
    ST_FAIL                    = 7'd63;

localparam [5:0]
    CTRL_ST_PWRUP_WAIT = 6'd0,
    CTRL_ST_IDLE       = 6'd9,
    CTRL_ST_WR_CMD_LO  = 6'd20,
    CTRL_ST_WR_CMD_HI  = 6'd21,
    CTRL_ST_TWR        = 6'd22;

localparam [7:0]
    ERR_REQ_READY_TIMEOUT   = 8'h01,
    ERR_REQ_ACCEPT_TIMEOUT  = 8'h02,
    ERR_RESP_TIMEOUT        = 8'h03,
    ERR_UNEXPECTED_RESP_ERR = 8'h04,
    ERR_READBACK_MISMATCH   = 8'h05,
    ERR_MISSING_RESP_ERR    = 8'h06,
    ERR_REFRESH_MISSING     = 8'h07,
    ERR_IDLE_DRAIN_TIMEOUT  = 8'h08,
    ERR_WRITE_STAGE_TIMEOUT = 8'h09,
    ERR_RESET_REINIT_STATE  = 8'h0a,
    ERR_RESET_READY_TIMEOUT = 8'h0b;

localparam [31:0] ADDR_BASE         = 32'h0000_0040;
localparam [31:0] ADDR_BANK_ROW     = 32'h0012_0440;
localparam [31:0] ADDR_BANK_ROW_HIGH = 32'h0112_0440;
localparam [31:0] ADDR_RESET_TARGET = 32'h0012_0480;
localparam [31:0] ADDR_MISALIGNED_R = 32'h0000_0042;
localparam [31:0] ADDR_MISALIGNED_W = 32'h0012_0482;

localparam [31:0] DATA_BASE         = 32'h1234_abcd;
localparam [31:0] DATA_PARTIAL      = 32'hdead_beef;
localparam [31:0] DATA_PARTIAL_EXP  = 32'h1234_beef;
localparam [31:0] DATA_BANK_ROW     = 32'hcafe_babe;
localparam [31:0] DATA_BANK_ROW_HIGH = 32'h1357_9bdf;
localparam [31:0] DATA_RESET_TARGET = 32'h0bad_f00d;

reg [6:0]  state;
reg [6:0]  after_op_state;
reg [23:0] wait_count;
reg [15:0] refresh_cmd_count;
reg [15:0] pressure_refresh_base;
reg [7:0]  pressure_resp_count;
reg [7:0]  local_reset_count;
reg        op_expect_err;
reg        op_expect_rdata_valid;
reg [7:0]  current_case_id;
reg [7:0]  current_step_id;
reg [31:0] expected_rdata;

wire refresh_cmd_seen;
wire [31:0] dbg_state_info;

assign refresh_cmd_seen = !sdram_cs_n && !sdram_ras_n && !sdram_cas_n && sdram_we_n;
assign dbg_state_info = {26'd0, dbg_state};

task latch_fail;
    input [7:0] case_id;
    input [7:0] step_id;
    input [7:0] error_code;
    input [31:0] info_value;
    input [31:0] expected_value;
    input [31:0] actual_value;
    begin
        req_valid <= 1'b0;
        ctrl_local_reset <= 1'b0;
        status_led <= 4'b1111;
        report_valid <= 1'b1;
        report_fail <= 1'b1;
        report_case_id <= case_id;
        report_step_id <= step_id;
        report_error_code <= error_code;
        report_info <= info_value;
        report_expected <= expected_value;
        report_actual <= actual_value;
        wait_count <= 24'd0;
        state <= ST_FAIL;
    end
endtask

task latch_pass;
    input [7:0] case_id;
    input [31:0] info_value;
    begin
        req_valid <= 1'b0;
        ctrl_local_reset <= 1'b0;
        status_led <= 4'b1000;
        report_valid <= 1'b1;
        report_fail <= 1'b0;
        report_case_id <= case_id;
        report_step_id <= 8'd0;
        report_error_code <= 8'd0;
        report_info <= info_value;
        report_expected <= 32'd0;
        report_actual <= 32'd0;
        wait_count <= 24'd0;
        state <= ST_PASS;
    end
endtask

always @(posedge clk) begin
    if (reset) begin
        req_valid <= 1'b0;
        req_we <= 1'b0;
        req_addr <= 32'd0;
        req_wdata <= 32'd0;
        req_wstrb <= 4'd0;
        ctrl_local_reset <= 1'b0;
        status_led <= 4'b0001;
        report_valid <= 1'b0;
        report_fail <= 1'b0;
        report_case_id <= 8'd0;
        report_step_id <= 8'd0;
        report_error_code <= 8'd0;
        report_info <= 32'd0;
        report_expected <= 32'd0;
        report_actual <= 32'd0;
        state <= ST_WAIT_INIT;
        after_op_state <= ST_WAIT_INIT;
        wait_count <= 24'd0;
        refresh_cmd_count <= 16'd0;
        pressure_refresh_base <= 16'd0;
        pressure_resp_count <= 8'd0;
        local_reset_count <= 8'd0;
        op_expect_err <= 1'b0;
        op_expect_rdata_valid <= 1'b0;
        current_case_id <= 8'd0;
        current_step_id <= 8'd0;
        expected_rdata <= 32'd0;
    end else begin
        report_valid <= 1'b0;

        if (refresh_cmd_seen && refresh_cmd_count != 16'hffff) begin
            refresh_cmd_count <= refresh_cmd_count + 16'd1;
        end

        case (state)
            ST_WAIT_INIT: begin
                req_valid <= 1'b0;
                ctrl_local_reset <= 1'b0;
                status_led <= 4'b0001;
                current_case_id <= 8'd0;
                current_step_id <= 8'd0;
                if (req_ready) begin
                    wait_count <= 24'd0;
                    state <= ST_PREP_CASE1_WRITE;
                end else if (wait_count >= WAIT_TIMEOUT_CYCLES) begin
                    latch_fail(8'h00, 8'h00, ERR_REQ_READY_TIMEOUT,
                               dbg_state_info, WAIT_TIMEOUT_CYCLES, wait_count);
                end else begin
                    wait_count <= wait_count + 24'd1;
                end
            end

            ST_PREP_CASE1_WRITE: begin
                status_led <= 4'b0010;
                current_case_id <= 8'h01;
                current_step_id <= 8'h01;
                req_we <= 1'b1;
                req_addr <= ADDR_BASE;
                req_wdata <= DATA_BASE;
                req_wstrb <= 4'hf;
                expected_rdata <= 32'd0;
                op_expect_err <= 1'b0;
                op_expect_rdata_valid <= 1'b0;
                after_op_state <= ST_PREP_CASE1_READ;
                wait_count <= 24'd0;
                state <= ST_OP_WAIT_READY;
            end

            ST_PREP_CASE1_READ: begin
                status_led <= 4'b0010;
                current_case_id <= 8'h01;
                current_step_id <= 8'h02;
                req_we <= 1'b0;
                req_addr <= ADDR_BASE;
                req_wdata <= 32'd0;
                req_wstrb <= 4'd0;
                expected_rdata <= DATA_BASE;
                op_expect_err <= 1'b0;
                op_expect_rdata_valid <= 1'b1;
                after_op_state <= ST_PREP_CASE2_WRITE;
                wait_count <= 24'd0;
                state <= ST_OP_WAIT_READY;
            end

            ST_PREP_CASE2_WRITE: begin
                status_led <= 4'b0010;
                current_case_id <= 8'h02;
                current_step_id <= 8'h01;
                req_we <= 1'b1;
                req_addr <= ADDR_BASE;
                req_wdata <= DATA_PARTIAL;
                req_wstrb <= 4'b0011;
                expected_rdata <= 32'd0;
                op_expect_err <= 1'b0;
                op_expect_rdata_valid <= 1'b0;
                after_op_state <= ST_PREP_CASE2_READ;
                wait_count <= 24'd0;
                state <= ST_OP_WAIT_READY;
            end

            ST_PREP_CASE2_READ: begin
                status_led <= 4'b0010;
                current_case_id <= 8'h02;
                current_step_id <= 8'h02;
                req_we <= 1'b0;
                req_addr <= ADDR_BASE;
                req_wdata <= 32'd0;
                req_wstrb <= 4'd0;
                expected_rdata <= DATA_PARTIAL_EXP;
                op_expect_err <= 1'b0;
                op_expect_rdata_valid <= 1'b1;
                after_op_state <= ST_PREP_CASE3_WRITE;
                wait_count <= 24'd0;
                state <= ST_OP_WAIT_READY;
            end

            ST_PREP_CASE3_WRITE: begin
                status_led <= 4'b0010;
                current_case_id <= 8'h03;
                current_step_id <= 8'h01;
                req_we <= 1'b1;
                req_addr <= ADDR_BANK_ROW;
                req_wdata <= DATA_BANK_ROW;
                req_wstrb <= 4'hf;
                expected_rdata <= 32'd0;
                op_expect_err <= 1'b0;
                op_expect_rdata_valid <= 1'b0;
                after_op_state <= ST_PREP_CASE3_WRITE_HIGH;
                wait_count <= 24'd0;
                state <= ST_OP_WAIT_READY;
            end

            ST_PREP_CASE3_WRITE_HIGH: begin
                status_led <= 4'b0010;
                current_case_id <= 8'h03;
                current_step_id <= 8'h02;
                req_we <= 1'b1;
                req_addr <= ADDR_BANK_ROW_HIGH;
                req_wdata <= DATA_BANK_ROW_HIGH;
                req_wstrb <= 4'hf;
                expected_rdata <= 32'd0;
                op_expect_err <= 1'b0;
                op_expect_rdata_valid <= 1'b0;
                after_op_state <= ST_PREP_CASE3_READ;
                wait_count <= 24'd0;
                state <= ST_OP_WAIT_READY;
            end

            ST_PREP_CASE3_READ: begin
                status_led <= 4'b0010;
                current_case_id <= 8'h03;
                current_step_id <= 8'h03;
                req_we <= 1'b0;
                req_addr <= ADDR_BANK_ROW;
                req_wdata <= 32'd0;
                req_wstrb <= 4'd0;
                expected_rdata <= DATA_BANK_ROW;
                op_expect_err <= 1'b0;
                op_expect_rdata_valid <= 1'b1;
                after_op_state <= ST_PREP_CASE3_READ_HIGH;
                wait_count <= 24'd0;
                state <= ST_OP_WAIT_READY;
            end

            ST_PREP_CASE3_READ_HIGH: begin
                status_led <= 4'b0010;
                current_case_id <= 8'h03;
                current_step_id <= 8'h04;
                req_we <= 1'b0;
                req_addr <= ADDR_BANK_ROW_HIGH;
                req_wdata <= 32'd0;
                req_wstrb <= 4'd0;
                expected_rdata <= DATA_BANK_ROW_HIGH;
                op_expect_err <= 1'b0;
                op_expect_rdata_valid <= 1'b1;
                after_op_state <= ST_PREP_CASE4_READ;
                wait_count <= 24'd0;
                state <= ST_OP_WAIT_READY;
            end

            ST_PREP_CASE4_READ: begin
                status_led <= 4'b0010;
                current_case_id <= 8'h04;
                current_step_id <= 8'h01;
                req_we <= 1'b0;
                req_addr <= ADDR_MISALIGNED_R;
                req_wdata <= 32'd0;
                req_wstrb <= 4'd0;
                expected_rdata <= 32'd0;
                op_expect_err <= 1'b1;
                op_expect_rdata_valid <= 1'b0;
                after_op_state <= ST_PREP_CASE5_WRITE;
                wait_count <= 24'd0;
                state <= ST_OP_WAIT_READY;
            end

            ST_PREP_CASE5_WRITE: begin
                status_led <= 4'b0010;
                current_case_id <= 8'h05;
                current_step_id <= 8'h01;
                req_we <= 1'b1;
                req_addr <= ADDR_MISALIGNED_W;
                req_wdata <= DATA_RESET_TARGET;
                req_wstrb <= 4'hf;
                expected_rdata <= 32'd0;
                op_expect_err <= 1'b1;
                op_expect_rdata_valid <= 1'b0;
                after_op_state <= ST_CASE6_PRESSURE_SETUP;
                wait_count <= 24'd0;
                state <= ST_OP_WAIT_READY;
            end

            ST_OP_WAIT_READY: begin
                status_led <= 4'b0010;
                req_valid <= 1'b0;
                ctrl_local_reset <= 1'b0;
                if (req_ready) begin
                    req_valid <= 1'b1;
                    wait_count <= 24'd0;
                    state <= ST_OP_WAIT_ACCEPT;
                end else if (wait_count >= WAIT_TIMEOUT_CYCLES) begin
                    latch_fail(current_case_id, current_step_id, ERR_REQ_READY_TIMEOUT,
                               dbg_state_info, WAIT_TIMEOUT_CYCLES, wait_count);
                end else begin
                    wait_count <= wait_count + 24'd1;
                end
            end

            ST_OP_WAIT_ACCEPT: begin
                status_led <= 4'b0010;
                req_valid <= 1'b1;
                ctrl_local_reset <= 1'b0;
                if (!req_ready) begin
                    req_valid <= 1'b0;
                    wait_count <= 24'd0;
                    state <= ST_OP_WAIT_RESP;
                end else if (wait_count >= WAIT_TIMEOUT_CYCLES) begin
                    latch_fail(current_case_id, current_step_id, ERR_REQ_ACCEPT_TIMEOUT,
                               dbg_state_info, WAIT_TIMEOUT_CYCLES, wait_count);
                end else begin
                    wait_count <= wait_count + 24'd1;
                end
            end

            ST_OP_WAIT_RESP: begin
                status_led <= 4'b0010;
                req_valid <= 1'b0;
                ctrl_local_reset <= 1'b0;
                if (resp_valid) begin
                    if (op_expect_err) begin
                        if (!resp_err) begin
                            latch_fail(current_case_id, current_step_id, ERR_MISSING_RESP_ERR,
                                       req_addr, 32'h0000_0001, 32'h0000_0000);
                        end else begin
                            wait_count <= 24'd0;
                            state <= after_op_state;
                        end
                    end else if (resp_err) begin
                        latch_fail(current_case_id, current_step_id, ERR_UNEXPECTED_RESP_ERR,
                                   req_addr, 32'h0000_0000, 32'h0000_0001);
                    end else if (op_expect_rdata_valid && resp_rdata != expected_rdata) begin
                        latch_fail(current_case_id, current_step_id, ERR_READBACK_MISMATCH,
                                   req_addr, expected_rdata, resp_rdata);
                    end else if (after_op_state == ST_PASS) begin
                        latch_pass(current_case_id, {16'd0, refresh_cmd_count});
                    end else begin
                        wait_count <= 24'd0;
                        state <= after_op_state;
                    end
                end else if (wait_count >= WAIT_TIMEOUT_CYCLES) begin
                    latch_fail(current_case_id, current_step_id, ERR_RESP_TIMEOUT,
                               dbg_state_info, WAIT_TIMEOUT_CYCLES, wait_count);
                end else begin
                    wait_count <= wait_count + 24'd1;
                end
            end

            ST_CASE6_PRESSURE_SETUP: begin
                status_led <= 4'b0100;
                current_case_id <= 8'h06;
                current_step_id <= 8'h01;
                req_valid <= 1'b0;
                req_we <= 1'b0;
                req_addr <= ADDR_BANK_ROW;
                req_wdata <= 32'd0;
                req_wstrb <= 4'd0;
                ctrl_local_reset <= 1'b0;
                if (req_ready) begin
                    pressure_refresh_base <= refresh_cmd_count;
                    pressure_resp_count <= 8'd0;
                    req_valid <= 1'b1;
                    wait_count <= 24'd0;
                    state <= ST_CASE6_PRESSURE_RUN;
                end else if (wait_count >= WAIT_TIMEOUT_CYCLES) begin
                    latch_fail(current_case_id, current_step_id, ERR_REQ_READY_TIMEOUT,
                               dbg_state_info, WAIT_TIMEOUT_CYCLES, wait_count);
                end else begin
                    wait_count <= wait_count + 24'd1;
                end
            end

            ST_CASE6_PRESSURE_RUN: begin
                status_led <= 4'b0100;
                req_valid <= 1'b1;
                ctrl_local_reset <= 1'b0;
                if (resp_valid && resp_err) begin
                    latch_fail(current_case_id, current_step_id, ERR_UNEXPECTED_RESP_ERR,
                               ADDR_BANK_ROW, 32'h0000_0000, 32'h0000_0001);
                end else if (resp_valid && (resp_rdata != DATA_BANK_ROW)) begin
                    latch_fail(current_case_id, current_step_id, ERR_READBACK_MISMATCH,
                               ADDR_BANK_ROW, DATA_BANK_ROW, resp_rdata);
                end else if ((refresh_cmd_count > pressure_refresh_base) &&
                             ((pressure_resp_count != 8'd0) ||
                              (resp_valid && (resp_rdata == DATA_BANK_ROW)))) begin
                    req_valid <= 1'b0;
                    current_step_id <= 8'h02;
                    wait_count <= 24'd0;
                    state <= ST_CASE6_PRESSURE_DRAIN;
                end else if (wait_count >= PRESSURE_TIMEOUT_CYCLES) begin
                    latch_fail(current_case_id, current_step_id, ERR_REFRESH_MISSING,
                               {16'd0, pressure_refresh_base},
                               {16'd0, pressure_refresh_base + 16'd1},
                               {16'd0, refresh_cmd_count});
                end else begin
                    if (resp_valid && (pressure_resp_count != 8'hff)) begin
                        pressure_resp_count <= pressure_resp_count + 8'd1;
                    end
                    wait_count <= wait_count + 24'd1;
                end
            end

            ST_CASE6_PRESSURE_DRAIN: begin
                status_led <= 4'b0100;
                req_valid <= 1'b0;
                ctrl_local_reset <= 1'b0;
                if (req_ready && (dbg_state == CTRL_ST_IDLE)) begin
                    wait_count <= 24'd0;
                    state <= ST_CASE7_PRIME_WAIT_READY;
                end else if (wait_count >= WAIT_TIMEOUT_CYCLES) begin
                    latch_fail(current_case_id, current_step_id, ERR_IDLE_DRAIN_TIMEOUT,
                               dbg_state_info, WAIT_TIMEOUT_CYCLES, wait_count);
                end else begin
                    wait_count <= wait_count + 24'd1;
                end
            end

            ST_CASE7_PRIME_WAIT_READY: begin
                status_led <= 4'b0010;
                current_case_id <= 8'h07;
                current_step_id <= 8'h01;
                req_valid <= 1'b0;
                req_we <= 1'b1;
                req_addr <= ADDR_RESET_TARGET;
                req_wdata <= DATA_RESET_TARGET;
                req_wstrb <= 4'hf;
                ctrl_local_reset <= 1'b0;
                if (req_ready) begin
                    req_valid <= 1'b1;
                    wait_count <= 24'd0;
                    state <= ST_CASE7_PRIME_WAIT_ACCEPT;
                end else if (wait_count >= WAIT_TIMEOUT_CYCLES) begin
                    latch_fail(current_case_id, current_step_id, ERR_REQ_READY_TIMEOUT,
                               dbg_state_info, WAIT_TIMEOUT_CYCLES, wait_count);
                end else begin
                    wait_count <= wait_count + 24'd1;
                end
            end

            ST_CASE7_PRIME_WAIT_ACCEPT: begin
                status_led <= 4'b0010;
                req_valid <= 1'b1;
                ctrl_local_reset <= 1'b0;
                if (!req_ready) begin
                    req_valid <= 1'b0;
                    wait_count <= 24'd0;
                    state <= ST_CASE7_WAIT_WRITE_STAGE;
                end else if (wait_count >= WAIT_TIMEOUT_CYCLES) begin
                    latch_fail(current_case_id, current_step_id, ERR_REQ_ACCEPT_TIMEOUT,
                               dbg_state_info, WAIT_TIMEOUT_CYCLES, wait_count);
                end else begin
                    wait_count <= wait_count + 24'd1;
                end
            end

            ST_CASE7_WAIT_WRITE_STAGE: begin
                status_led <= 4'b0010;
                req_valid <= 1'b0;
                ctrl_local_reset <= 1'b0;
                if ((dbg_state == CTRL_ST_WR_CMD_LO) ||
                    (dbg_state == CTRL_ST_WR_CMD_HI) ||
                    (dbg_state == CTRL_ST_TWR)) begin
                    current_step_id <= 8'h02;
                    ctrl_local_reset <= 1'b1;
                    if (LOCAL_RESET_HOLD_CYCLES > 0) begin
                        local_reset_count <= LOCAL_RESET_HOLD_CYCLES - 8'd1;
                    end else begin
                        local_reset_count <= 8'd0;
                    end
                    wait_count <= 24'd0;
                    state <= ST_CASE7_ASSERT_RESET;
                end else if (wait_count >= WAIT_TIMEOUT_CYCLES) begin
                    latch_fail(current_case_id, current_step_id, ERR_WRITE_STAGE_TIMEOUT,
                               dbg_state_info, WAIT_TIMEOUT_CYCLES, wait_count);
                end else begin
                    wait_count <= wait_count + 24'd1;
                end
            end

            ST_CASE7_ASSERT_RESET: begin
                status_led <= 4'b0010;
                req_valid <= 1'b0;
                ctrl_local_reset <= 1'b1;
                if (local_reset_count == 8'd0) begin
                    ctrl_local_reset <= 1'b0;
                    current_step_id <= 8'h03;
                    wait_count <= 24'd0;
                    state <= ST_CASE7_WAIT_POR_STATE;
                end else begin
                    local_reset_count <= local_reset_count - 8'd1;
                end
            end

            ST_CASE7_WAIT_POR_STATE: begin
                status_led <= 4'b0001;
                req_valid <= 1'b0;
                ctrl_local_reset <= 1'b0;
                if (dbg_state == CTRL_ST_PWRUP_WAIT) begin
                    wait_count <= 24'd0;
                    state <= ST_CASE7_WAIT_CTRL_READY;
                end else if (wait_count >= WAIT_TIMEOUT_CYCLES) begin
                    latch_fail(current_case_id, current_step_id, ERR_RESET_REINIT_STATE,
                               dbg_state_info, {26'd0, CTRL_ST_PWRUP_WAIT}, dbg_state_info);
                end else begin
                    wait_count <= wait_count + 24'd1;
                end
            end

            ST_CASE7_WAIT_CTRL_READY: begin
                status_led <= 4'b0001;
                req_valid <= 1'b0;
                ctrl_local_reset <= 1'b0;
                if (req_ready) begin
                    wait_count <= 24'd0;
                    state <= ST_PREP_CASE7_WRITE;
                end else if (wait_count >= WAIT_TIMEOUT_CYCLES) begin
                    latch_fail(current_case_id, current_step_id, ERR_RESET_READY_TIMEOUT,
                               dbg_state_info, WAIT_TIMEOUT_CYCLES, wait_count);
                end else begin
                    wait_count <= wait_count + 24'd1;
                end
            end

            ST_PREP_CASE7_WRITE: begin
                status_led <= 4'b0010;
                current_case_id <= 8'h07;
                current_step_id <= 8'h04;
                req_we <= 1'b1;
                req_addr <= ADDR_RESET_TARGET;
                req_wdata <= DATA_RESET_TARGET;
                req_wstrb <= 4'hf;
                expected_rdata <= 32'd0;
                op_expect_err <= 1'b0;
                op_expect_rdata_valid <= 1'b0;
                after_op_state <= ST_PREP_CASE7_READ;
                wait_count <= 24'd0;
                state <= ST_OP_WAIT_READY;
            end

            ST_PREP_CASE7_READ: begin
                status_led <= 4'b0010;
                current_case_id <= 8'h07;
                current_step_id <= 8'h05;
                req_we <= 1'b0;
                req_addr <= ADDR_RESET_TARGET;
                req_wdata <= 32'd0;
                req_wstrb <= 4'd0;
                expected_rdata <= DATA_RESET_TARGET;
                op_expect_err <= 1'b0;
                op_expect_rdata_valid <= 1'b1;
                after_op_state <= ST_PASS;
                wait_count <= 24'd0;
                state <= ST_OP_WAIT_READY;
            end

            ST_PASS: begin
                status_led <= 4'b1000;
                req_valid <= 1'b0;
                ctrl_local_reset <= 1'b0;
            end

            ST_FAIL: begin
                status_led <= 4'b1111;
                req_valid <= 1'b0;
                ctrl_local_reset <= 1'b0;
            end

            default: begin
                latch_fail(8'hff, 8'hff, 8'hff, 32'hffff_ffff, 32'd0, 32'd0);
            end
        endcase
    end
end

endmodule
