//by GPT 5.3 codex
// - This is intentionally conservative for bring-up.
// - Explicit PRECHARGE after each request (closed-page).
// - Refresh is scheduled in IDLE; periodic due can be deferred slightly,
//   but an overdue window will force the next IDLE slot to refresh first.
// - Non word-aligned accesses are rejected with resp_err.
//
// Style follows existing probe RTL in this repository (explicit state machine,
// cycle counters, simple command encoding).

module sdram_data_ctrl #(
    parameter integer PWRUP_WAIT_CYCLES   = 16'd10000,
    parameter integer TRP_CYCLES          = 16'd3,
    parameter integer TRFC_CYCLES         = 16'd7,
    parameter integer TMRD_CYCLES         = 16'd2,
    parameter integer TRCD_CYCLES         = 16'd3,
    parameter integer TWR_CYCLES          = 16'd3,
    parameter integer CAS_LATENCY_CYCLES  = 16'd2,
    parameter integer REFI_CYCLES         = 16'd780,   // example @50MHz for ~15.6us
    parameter integer REFRESH_DEFER_CYCLES = 16'd100,  // allow a small overdue window
    parameter [12:0] MODE_REG_VALUE       = 13'h220    // BL=1, sequential, CL=2 (example)
) (
    input              clk,
    input              reset,

    // host request interface (single outstanding)
    input              req_valid,
    output reg         req_ready,
    input              req_we,
    input      [31:0]  req_addr,   // byte address
    input      [31:0]  req_wdata,
    input      [3:0]   req_wstrb,
    output reg         resp_valid,
    output reg [31:0]  resp_rdata,
    output reg         resp_err,

    // SDRAM DQ data path
    input      [15:0]  dq_in,
    output reg         dq_oe,
    output reg [15:0]  dq_out,

    // SDRAM command/address pins
    output reg         sdram_cke,
    output reg         sdram_cs_n,
    output reg         sdram_ras_n,
    output reg         sdram_cas_n,
    output reg         sdram_we_n,
    output reg [1:0]   sdram_ba,
    output reg [12:0]  sdram_addr,
    output reg [1:0]   sdram_dqm,

    // optional debug
    output reg [5:0]   dbg_state,
    output reg         dbg_refresh_pending
);

localparam [5:0]
    ST_PWRUP_WAIT   = 6'd0,
    ST_WAIT_PWRUP   = 6'd26,
    ST_INIT_PRE     = 6'd1,
    ST_INIT_TRP     = 6'd2,
    ST_INIT_AR1     = 6'd3,
    ST_INIT_TRFC1   = 6'd4,
    ST_INIT_AR2     = 6'd5,
    ST_INIT_TRFC2   = 6'd6,
    ST_INIT_MRS     = 6'd7,
    ST_INIT_TMRD    = 6'd8,

    ST_IDLE         = 6'd9,
    ST_REF_CMD      = 6'd10,
    ST_REF_TRFC     = 6'd11,

    ST_ACT          = 6'd12,
    ST_TRCD         = 6'd13,

    ST_RD_CMD_LO    = 6'd14,
    ST_RD_CL_LO     = 6'd15,
    ST_RD_CAP_LO    = 6'd16,
    ST_RD_CMD_HI    = 6'd17,
    ST_RD_CL_HI     = 6'd18,
    ST_RD_CAP_HI    = 6'd19,

    ST_WR_CMD_LO    = 6'd20,
    ST_WR_CMD_HI    = 6'd21,
    ST_TWR          = 6'd22,

    ST_PRE          = 6'd23,
    ST_TRP          = 6'd24,
    ST_RESP         = 6'd25;

reg [5:0]  state;
reg [15:0] wait_count;
reg [15:0] refresh_age;
reg        refresh_pending;
reg        busy;
reg        force_refresh;       // 强制刷新标志

reg [31:0] latched_addr;
reg [31:0] latched_wdata;
reg [3:0]  latched_wstrb;
reg        latched_we;
reg        latched_misaligned;

reg [15:0] rd_lo;
reg [15:0] rd_hi;

reg [11:0] row_addr;
reg [1:0]  bank_addr;
reg [8:0]  col_addr_lo;
reg [8:0]  col_addr_hi;

wire [22:0] haddr = latched_addr[23:1]; // halfword address

// command helpers (active-low control signals)
task cmd_nop;
begin
    sdram_cs_n  <= 1'b0;
    sdram_ras_n <= 1'b1;
    sdram_cas_n <= 1'b1;
    sdram_we_n  <= 1'b1;
end
endtask

task cmd_precharge_all;
begin
    sdram_cs_n  <= 1'b0;
    sdram_ras_n <= 1'b0;
    sdram_cas_n <= 1'b1;
    sdram_we_n  <= 1'b0;
    sdram_ba    <= 2'b00;
    sdram_addr  <= 13'b0100_0000_0000; // A10=1, 其他为0
end
endtask

task cmd_precharge_bank;
    input [1:0] ba;
begin
    sdram_cs_n  <= 1'b0;
    sdram_ras_n <= 1'b0;
    sdram_cas_n <= 1'b1;
    sdram_we_n  <= 1'b0;
    sdram_ba    <= ba;
    sdram_addr  <= 13'b0000_0000_0000; // A10=0
end
endtask


task cmd_auto_refresh;
begin
    sdram_cs_n  <= 1'b0;
    sdram_ras_n <= 1'b0;
    sdram_cas_n <= 1'b0;
    sdram_we_n  <= 1'b1;
    sdram_ba    <= 2'b00;
    sdram_addr  <= 13'd0;
end
endtask

task cmd_load_mode;
begin
    sdram_cs_n  <= 1'b0;
    sdram_ras_n <= 1'b0;
    sdram_cas_n <= 1'b0;
    sdram_we_n  <= 1'b0;
    sdram_ba    <= 2'b00;
    sdram_addr  <= MODE_REG_VALUE;
end
endtask

task cmd_active;
    input [1:0] ba;
    input [11:0] row;
begin
    sdram_cs_n  <= 1'b0;
    sdram_ras_n <= 1'b0;
    sdram_cas_n <= 1'b1;
    sdram_we_n  <= 1'b1;
    sdram_ba    <= ba;
    sdram_addr  <= {1'b0, row}; // A[12:0], row uses low 12 bits in this mapping
end
endtask

task cmd_read;
    input [1:0] ba;
    input [8:0] col;
begin
    sdram_cs_n  <= 1'b0;
    sdram_ras_n <= 1'b1;
    sdram_cas_n <= 1'b0;
    sdram_we_n  <= 1'b1;
    sdram_ba    <= ba;
    // A10=0 (no auto-precharge), column in A[8:0]
    sdram_addr  <= {3'b000, 1'b0, col};
end
endtask

task cmd_write;
    input [1:0] ba;
    input [8:0] col;
begin
    sdram_cs_n  <= 1'b0;
    sdram_ras_n <= 1'b1;
    sdram_cas_n <= 1'b0;
    sdram_we_n  <= 1'b0;
    sdram_ba    <= ba;
    // A10=0 (no auto-precharge), column in A[8:0]
    sdram_addr  <= {3'b000, 1'b0, col};
end
endtask

always @(posedge clk) begin
    if (reset) begin
        state <= ST_PWRUP_WAIT;
        wait_count <= 16'd0;
        refresh_age <= 16'd0;
        refresh_pending <= 1'b0;
        busy <= 1'b0;
        force_refresh <= 1'b0;

        req_ready <= 1'b0;
        resp_valid <= 1'b0;
        resp_rdata <= 32'd0;
        resp_err <= 1'b0;

        dq_oe = 1'b0;
        dq_out = 16'd0;
        sdram_dqm <= 2'b00;

        sdram_cke <= 1'b1;
        sdram_cs_n <= 1'b0;
        sdram_ras_n <= 1'b1;
        sdram_cas_n <= 1'b1;
        sdram_we_n <= 1'b1;
        sdram_ba <= 2'b00;
        sdram_addr <= 13'd0;

        rd_lo <= 16'd0;
        rd_hi <= 16'd0;

        latched_addr <= 32'd0;
        latched_wdata <= 32'd0;
        latched_wstrb <= 4'd0;
        latched_we <= 1'b0;
        latched_misaligned <= 1'b0;

        row_addr <= 12'd0;
        bank_addr <= 2'd0;
        col_addr_lo <= 9'd0;
        col_addr_hi <= 9'd0;

        dbg_state <= ST_PWRUP_WAIT;
        dbg_refresh_pending <= 1'b0;
    end else begin
        // defaults each cycle
        req_ready <= 1'b0;
        resp_valid <= 1'b0;
        resp_err   <= 1'b0;
        dq_oe      = 1'b0;
        sdram_dqm  <= 2'b00;
        cmd_nop();

        // refresh age：统计距离上一次“实际发出 refresh 命令”已经过了多久。
        // refresh_pending 表示已到周期点，但允许继续服务一小段请求；
        // force_refresh 表示已经拖到 overdue 窗口，下一次回到 IDLE 必须先 refresh。
        if (state >= ST_IDLE) begin
            if (refresh_age < 16'hffff) begin
                refresh_age <= refresh_age + 16'd1;
            end

            if (refresh_age >= (REFI_CYCLES - 1)) begin
                refresh_pending <= 1'b1;
            end

            if (refresh_age >= (REFI_CYCLES + REFRESH_DEFER_CYCLES - 1)) begin
                force_refresh <= 1'b1;
            end
        end else begin
            refresh_age <= 16'd0;
            refresh_pending <= 1'b0;
            force_refresh <= 1'b0;  // 初始化期间不触发
        end

        case (state)
            ST_PWRUP_WAIT: begin
                req_ready  <= 1'b0;
                wait_count <= PWRUP_WAIT_CYCLES[15:0];
                state      <= ST_WAIT_PWRUP;
            end

            ST_WAIT_PWRUP: begin
                if (wait_count != 16'd0) begin
                    wait_count <= wait_count - 16'd1;
                end else begin
                    state <= ST_INIT_PRE;
                end
            end

            ST_INIT_PRE: begin
                // 对齐 probe/smoke：第一条必须 PRECHARGE ALL (A10=1)
                cmd_precharge_all();
                wait_count <= TRP_CYCLES[15:0];
                state <= ST_INIT_TRP;
            end

            ST_INIT_TRP: begin
                if (wait_count != 16'd0) begin
                    wait_count <= wait_count - 16'd1;
                end else begin
                    state <= ST_INIT_AR1;
                end
            end

            ST_INIT_AR1: begin
                cmd_auto_refresh();
                wait_count <= TRFC_CYCLES[15:0];
                state <= ST_INIT_TRFC1;
            end

            ST_INIT_TRFC1: begin
                if (wait_count != 16'd0) begin
                    wait_count <= wait_count - 16'd1;
                end else begin
                    state <= ST_INIT_AR2;
                end
            end

            ST_INIT_AR2: begin
                cmd_auto_refresh();
                wait_count <= TRFC_CYCLES[15:0];
                state <= ST_INIT_TRFC2;
            end

            ST_INIT_TRFC2: begin
                if (wait_count != 16'd0) begin
                    wait_count <= wait_count - 16'd1;
                end else begin
                    state <= ST_INIT_MRS;
                end
            end

            ST_INIT_MRS: begin
                cmd_load_mode();
                wait_count <= TMRD_CYCLES[15:0];
                state <= ST_INIT_TMRD;
            end

            ST_INIT_TMRD: begin
                if (wait_count != 16'd0) begin
                    wait_count <= wait_count - 16'd1;
                end else begin
                    req_ready <= 1'b1;
                    busy <= 1'b0;
                    state <= ST_IDLE;
                end
            end

            ST_IDLE: begin
                req_ready <= 1'b0;
                
                if (!busy) begin
                    if (force_refresh) begin
                        cmd_auto_refresh();
                        refresh_age <= 16'd0;
                        wait_count <= TRFC_CYCLES[15:0];
                        refresh_pending <= 1'b0;
                        force_refresh <= 1'b0;
                        state <= ST_REF_TRFC;
                    end
                    else if (req_valid) begin
                        // 接受主机请求
                        latched_addr <= req_addr;
                        latched_we   <= req_we;
                        latched_wdata <= req_wdata;
                        latched_wstrb <= req_wstrb;
                        latched_misaligned <= |req_addr[1:0];
                        busy <= 1'b1;
                        // req_ready 已默认 0，无需额外操作
                        
                        if (|req_addr[1:0]) begin
                            state <= ST_RESP;   // 直接返回错误
                        end else begin
                            row_addr    <= req_addr[23:12];
                            bank_addr   <= req_addr[11:10];
                            col_addr_lo <= req_addr[9:1];
                            col_addr_hi <= req_addr[9:1] + 9'd1;
                            cmd_active(req_addr[11:10], req_addr[23:12]);
                            wait_count <= TRCD_CYCLES[15:0];
                            state <= ST_TRCD;
                        end
                    end
                    else if (refresh_pending) begin
                        cmd_auto_refresh();
                        refresh_age <= 16'd0;
                        wait_count <= TRFC_CYCLES[15:0];
                        refresh_pending <= 1'b0;
                        force_refresh <= 1'b0;
                        state <= ST_REF_TRFC;
                    end
                    else begin
                        // 真正空闲，允许新请求
                        req_ready <= 1'b1;
                    end
                end
            end

            ST_REF_TRFC: begin
                if (wait_count != 16'd0) begin
                    wait_count <= wait_count - 16'd1;
                end else begin
                    state <= ST_IDLE;
                end
            end

            ST_TRCD: begin
                if (wait_count == 1 && latched_we) begin
                    dq_oe = 1'b1;
                    dq_out = latched_wdata[15:0];   // 低半字提前一个周期准备好
                end
                if (wait_count != 16'd0) begin
                    wait_count <= wait_count - 16'd1;
                end else if (latched_we) begin
                    state <= ST_WR_CMD_LO;
                end else begin
                    state <= ST_RD_CMD_LO;
                end
            end

            // Read low half
            ST_RD_CMD_LO: begin
                dq_oe = 1'b0;
                cmd_read(bank_addr, col_addr_lo);
                wait_count <= CAS_LATENCY_CYCLES[15:0];
                state <= ST_RD_CL_LO;
            end

            ST_RD_CL_LO: begin
                dq_oe = 1'b0;
                if (wait_count != 16'd0) begin
                    wait_count <= wait_count - 16'd1;
                end else begin
                    state <= ST_RD_CAP_LO;
                end
            end

            ST_RD_CAP_LO: begin
                dq_oe = 1'b0;
                rd_lo <= dq_in;
                state <= ST_RD_CMD_HI;
            end

            // Read high half
            ST_RD_CMD_HI: begin
                dq_oe = 1'b0;
                cmd_read(bank_addr, col_addr_hi);
                wait_count <= CAS_LATENCY_CYCLES[15:0];
                state <= ST_RD_CL_HI;
            end

            ST_RD_CL_HI: begin
                dq_oe = 1'b0;
                if (wait_count != 16'd0) begin
                    wait_count <= wait_count - 16'd1;
                end else begin
                    state <= ST_RD_CAP_HI;
                end
            end

            ST_RD_CAP_HI: begin
                dq_oe = 1'b0;
                rd_hi <= dq_in;
                state <= ST_PRE;
            end

            ST_WR_CMD_LO: begin
                dq_oe = 1'b1;                    // 保持
                //dq_out = latched_wdata[31:16];   // 准备高半字（当前周期低半字已稳定）
                sdram_dqm <= ~latched_wstrb[1:0];
                cmd_write(bank_addr, col_addr_lo);
                state <= ST_WR_CMD_HI;
            end

            // Write high half
            ST_WR_CMD_HI: begin
                dq_oe = 1'b1;                    // 保持，dq_out 已经是高半字
                dq_out = latched_wdata[31:16];   // 立即更新为高半字（阻塞）
                sdram_dqm <= ~latched_wstrb[3:2];
                cmd_write(bank_addr, col_addr_hi);
                wait_count <= TWR_CYCLES[15:0];
                state <= ST_TWR;
            end

            ST_TWR: begin
                dq_oe = 1'b0;                    // 拉低
                dq_out = 16'd0;
                if (wait_count != 16'd0) begin
                    wait_count <= wait_count - 16'd1;
                end else begin
                    state <= ST_PRE;
                end
            end

            ST_PRE: begin
                dq_oe = 1'b0;
                cmd_precharge_bank(bank_addr);
                wait_count <= TRP_CYCLES[15:0];
                state <= ST_TRP;
            end

            ST_TRP: begin
                dq_oe = 1'b0;
                if (wait_count != 16'd0) begin
                    wait_count <= wait_count - 16'd1;
                end else begin
                    state <= ST_RESP;
                end
            end

            ST_RESP: begin
                if (latched_misaligned) begin
                    resp_err <= 1'b1;
                    resp_rdata <= 32'd0;
                end else if (!latched_we) begin
                    resp_rdata <= {rd_hi, rd_lo};
                end
                resp_valid <= 1'b1;
                busy <= 1'b0;
                state <= ST_IDLE;
            end

            default: begin
                state <= ST_PWRUP_WAIT;
            end
        endcase

        dbg_state <= state;
        dbg_refresh_pending <= refresh_pending;
    end
end

endmodule
