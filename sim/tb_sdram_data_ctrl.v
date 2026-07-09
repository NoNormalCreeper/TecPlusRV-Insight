//by GPT 5.3 codex
`timescale 1ns/1ps

module tb_sdram_data_ctrl;

reg clk;
reg reset;

reg        req_valid;
wire       req_ready;
reg        req_we;
reg [31:0] req_addr;
reg [31:0] req_wdata;
reg [3:0]  req_wstrb;

wire       resp_valid;
wire [31:0] resp_rdata;
wire       resp_err;

reg [15:0] dq_in;
wire       dq_oe;
wire [15:0] dq_out;

wire       sdram_cke;
wire       sdram_cs_n;
wire       sdram_ras_n;
wire       sdram_cas_n;
wire       sdram_we_n;
wire [1:0] sdram_ba;
wire [12:0] sdram_addr;
wire [1:0] sdram_dqm;

wire [5:0] dbg_state;
wire       dbg_refresh_pending;

// make timing short for simulation
localparam integer PWRUP_WAIT_CYCLES  = 4;
localparam integer TRP_CYCLES         = 2;
localparam integer TRFC_CYCLES        = 3;
localparam integer TMRD_CYCLES        = 2;
localparam integer TRCD_CYCLES        = 2;
localparam integer TWR_CYCLES         = 2;
localparam integer CAS_LATENCY_CYCLES = 2;
localparam integer REFI_CYCLES        = 20;

sdram_data_ctrl #(
    .PWRUP_WAIT_CYCLES(PWRUP_WAIT_CYCLES),
    .TRP_CYCLES(TRP_CYCLES),
    .TRFC_CYCLES(TRFC_CYCLES),
    .TMRD_CYCLES(TMRD_CYCLES),
    .TRCD_CYCLES(TRCD_CYCLES),
    .TWR_CYCLES(TWR_CYCLES),
    .CAS_LATENCY_CYCLES(CAS_LATENCY_CYCLES),
    .REFI_CYCLES(REFI_CYCLES),
    .MODE_REG_VALUE(13'h220)
) dut (
    .clk(clk),
    .reset(reset),
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
    .sdram_cke(sdram_cke),
    .sdram_cs_n(sdram_cs_n),
    .sdram_ras_n(sdram_ras_n),
    .sdram_cas_n(sdram_cas_n),
    .sdram_we_n(sdram_we_n),
    .sdram_ba(sdram_ba),
    .sdram_addr(sdram_addr),
    .sdram_dqm(sdram_dqm),
    .dbg_state(dbg_state),
    .dbg_refresh_pending(dbg_refresh_pending)
);

always #10 clk = ~clk; // 50MHz

// simple memory model (word-addressed by {bank,row,col})
reg [15:0] mem [0:65535];

integer i;
integer init_stage;
integer refresh_seen;
integer read_wait;
reg      read_pending;
reg [15:0] read_data_latch;
integer cycles;
integer saw_refresh_cmd;
integer saw_write_cmd;
integer saw_read_cmd;
integer saw_misaligned_resp;
integer refresh_before_pressure;

function [15:0] mk_addr_key;
    input [1:0] ba;
    input [12:0] rowcol; // [12:0] row in ACT, col in READ/WRITE
    begin
        // lightweight hash key for TB storage
        mk_addr_key = {ba, rowcol[7:0], rowcol[11:8]};
    end
endfunction

reg [1:0] open_ba;
reg [12:0] open_row;
reg        row_open;

reg        expect_is_write;
integer    expect_phase;
reg [1:0]  expect_bank;
reg [11:0] expect_row;
reg [8:0]  expect_col_lo;
reg [8:0]  expect_col_hi;

initial begin
    clk = 1'b0;
    reset = 1'b1;
    req_valid = 1'b0;
    req_we = 1'b0;
    req_addr = 32'd0;
    req_wdata = 32'd0;
    req_wstrb = 4'h0;
    dq_in = 16'h0000;

    init_stage = 0;
    refresh_seen = 0;
    read_wait = 0;
    read_pending = 1'b0;
    read_data_latch = 16'd0;
    cycles = 0;
    saw_refresh_cmd = 0;
    saw_write_cmd = 0;
    saw_read_cmd = 0;
    saw_misaligned_resp = 0;
    refresh_before_pressure = 0;
    row_open = 1'b0;
    open_ba = 2'b00;
    open_row = 13'd0;
    expect_is_write = 1'b0;
    expect_phase = 0;
    expect_bank = 2'b00;
    expect_row = 12'd0;
    expect_col_lo = 9'd0;
    expect_col_hi = 9'd0;

    for (i = 0; i < 65536; i = i + 1) begin
        mem[i] = 16'h0000;
    end

    $dumpfile("sim/build/tb_sdram_data_ctrl.vcd");
    $dumpvars(0, tb_sdram_data_ctrl);

    #80;
    reset = 1'b0;

    // wait for init complete
    wait(req_ready === 1'b1);

    // 1) aligned write request
    host_write32(32'h0000_0040, 32'h1234_ABCD, 4'b1111);
    #1;//wait for a delta
    // 2) aligned read request
    host_read32(32'h0000_0040);
    if (resp_rdata !== 32'h1234_ABCD) begin
        $display("FAIL: readback mismatch, got=%h exp=%h", resp_rdata, 32'h1234_ABCD);
        $finish;
    end

    // 3) partial write + readback
    host_write32(32'h0000_0040, 32'hDEAD_BEEF, 4'b0011); // only low halfword
    host_read32(32'h0000_0040);
    if (resp_rdata !== 32'h1234_BEEF) begin
        $display("FAIL: partial write mismatch, got=%h exp=%h", resp_rdata, 32'h1234_BEEF);
        $finish;
    end

    // 4) 非零 row/bank 地址访问，固定“ACT 用旧地址”的回归
    host_write32(32'h0012_0440, 32'hCAFE_BABE, 4'b1111);
    host_read32(32'h0012_0440);
    if (resp_rdata !== 32'hCAFE_BABE) begin
        $display("FAIL: non-zero bank/row readback mismatch, got=%h exp=%h",
                 resp_rdata, 32'hCAFE_BABE);
        $finish;
    end

    // 5) misaligned access should error
    host_read32(32'h0000_0042);
    if (!resp_err) begin
        $display("FAIL: misaligned read did not raise resp_err");
        $finish;
    end
    saw_misaligned_resp = 1;

    // 6) 持续 req_valid=1 的流量下，仍然必须插入 refresh
    refresh_before_pressure = refresh_seen;
    start_read_pressure(32'h0012_0440);
    repeat (120) @(posedge clk);
    stop_read_pressure();
    if ((refresh_seen - refresh_before_pressure) == 0) begin
        $display("FAIL: refresh missing under continuous req_valid pressure");
        $finish;
    end

    // 7) 写事务进行到一半时 reset，控制器必须回到初始化并重新可用
    start_write32_no_wait(32'h0012_0480, 32'h0BAD_F00D, 4'b1111);
    wait(dut.state == 6'd20 || dut.state == 6'd21 || dut.state == 6'd22);
    pulse_reset_and_wait_reinit();
    host_write32(32'h0012_0480, 32'h0BAD_F00D, 4'b1111);
    host_read32(32'h0012_0480);
    if (resp_rdata !== 32'h0BAD_F00D) begin
        $display("FAIL: post-reset recovery readback mismatch, got=%h exp=%h",
                 resp_rdata, 32'h0BAD_F00D);
        $finish;
    end

    // 8) idle 一段时间，至少还能看到一次 refresh
    repeat (80) @(posedge clk);
    if (saw_refresh_cmd == 0) begin
        $display("FAIL: no refresh command observed");
        $finish;
    end

    if (saw_write_cmd == 0 || saw_read_cmd == 0) begin
        $display("FAIL: expected read/write commands not observed");
        $finish;
    end

    if (saw_misaligned_resp == 0) begin
        $display("FAIL: misaligned response path not covered");
        $finish;
    end

    $display("PASS: tb_sdram_data_ctrl");
    $finish;
end

task host_write32;
    input [31:0] addr;
    input [31:0] data;
    input [3:0]  wstrb;
begin
    @(posedge clk);
    while (!req_ready) @(posedge clk);
    arm_expected_access(addr, 1'b1);
    req_addr  = addr;
    req_wdata = data;
    req_wstrb = wstrb;
    req_we    = 1'b1;
    req_valid = 1'b1;
    while (req_ready) @(posedge clk);
    req_valid = 1'b0;
    req_we    = 1'b0;
    req_wstrb = 4'b0000;
    wait(resp_valid);
    if (resp_err) begin
        $display("FAIL: unexpected resp_err on write");
        $finish;
    end
    @(posedge clk);
end
endtask

task host_read32;
    input [31:0] addr;
begin
    @(posedge clk);
    while (!req_ready) @(posedge clk);
    if (addr[1:0] == 2'b00) begin
        arm_expected_access(addr, 1'b0);
    end
    req_addr  = addr;
    req_wdata = 32'd0;
    req_wstrb = 4'b0000;
    req_we    = 1'b0;
    req_valid = 1'b1;
    while (req_ready) @(posedge clk);
    req_valid = 1'b0;
    wait(resp_valid);
    @(posedge clk);
end
endtask

task arm_expected_access;
    input [31:0] addr;
    input        is_write;
begin
    expect_is_write = is_write;
    expect_phase = 1;
    expect_bank = addr[11:10];
    expect_row = addr[23:12];
    expect_col_lo = addr[9:1];
    expect_col_hi = addr[9:1] + 9'd1;
end
endtask

task start_read_pressure;
    input [31:0] addr;
begin
    @(posedge clk);
    while (!req_ready) @(posedge clk);
    req_addr  = addr;
    req_wdata = 32'd0;
    req_wstrb = 4'b0000;
    req_we    = 1'b0;
    req_valid = 1'b1;
end
endtask

task start_write32_no_wait;
    input [31:0] addr;
    input [31:0] data;
    input [3:0]  wstrb;
begin
    @(posedge clk);
    while (!req_ready) @(posedge clk);
    arm_expected_access(addr, 1'b1);
    req_addr  = addr;
    req_wdata = data;
    req_wstrb = wstrb;
    req_we    = 1'b1;
    req_valid = 1'b1;
    while (req_ready) @(posedge clk);
    req_valid = 1'b0;
    req_we    = 1'b0;
    req_wstrb = 4'b0000;
end
endtask

task stop_read_pressure;
begin
    @(posedge clk);
    req_valid = 1'b0;
    req_we = 1'b0;
    req_wstrb = 4'b0000;
    while (dut.busy) @(posedge clk);
    @(posedge clk);
end
endtask

task pulse_reset_and_wait_reinit;
begin
    @(negedge clk);
    reset = 1'b1;
    req_valid = 1'b0;
    req_we = 1'b0;
    req_wstrb = 4'b0000;
    expect_phase = 0;

    @(posedge clk);
    #1;
    if (dbg_state !== 6'd0) begin
        $display("FAIL: reset did not force ST_PWRUP_WAIT, state=%0d", dbg_state);
        $finish;
    end
    if (dut.busy !== 1'b0) begin
        $display("FAIL: reset did not clear busy");
        $finish;
    end
    if (req_ready !== 1'b0) begin
        $display("FAIL: req_ready should stay low during reset");
        $finish;
    end
    if (resp_valid !== 1'b0) begin
        $display("FAIL: resp_valid should be low during reset");
        $finish;
    end
    if (dq_oe !== 1'b0) begin
        $display("FAIL: dq_oe should drop low during reset");
        $finish;
    end

    @(posedge clk);
    @(negedge clk);
    reset = 1'b0;

    wait(req_ready === 1'b1);
    @(posedge clk);
end
endtask


// decode/observe SDRAM commands and emulate read data latency
always @(posedge clk) begin
    cycles <= cycles + 1;
    // wait a delta to observe DUT non-blocking updates from this posedge
    #1;
    //debug
//$display("DBG CMD t=%0t st=%0d busy=%b req_valid=%b dq_oe=%b dq_out=%h RAS=%b CAS=%b WE=%b A10=%b A=%h",
//$time, init_stage,dut.busy, req_valid, dq_oe, dq_out, sdram_ras_n, sdram_cas_n, sdram_we_n, sdram_addr[10], sdram_addr);
//if (!sdram_cs_n && !sdram_ras_n && sdram_cas_n && sdram_we_n) begin  // ACT 命令
//    $display("ACT: ba=%b, row=%h, req_addr=%h, latched_addr=%h, haddr=%h",
//             sdram_ba, sdram_addr, req_addr, dut.latched_addr, dut.haddr);
//end
    if (reset) begin
        row_open <= 1'b0;
        open_ba <= 2'b00;
        open_row <= 13'd0;
        read_wait <= 0;
        read_pending <= 1'b0;
        read_data_latch <= 16'd0;
        dq_in <= 16'h0000;
        expect_is_write <= 1'b0;
        expect_phase <= 0;
        expect_bank <= 2'b00;
        expect_row <= 12'd0;
        expect_col_lo <= 9'd0;
        expect_col_hi <= 9'd0;
        init_stage <= 0;
    end else begin
    // emit read data after CL countdown
    if (read_pending) begin
        if (read_wait == 0) begin
            dq_in <= read_data_latch;
            read_pending <= 1'b0;
        end else begin
            read_wait <= read_wait - 1;
        end
    end

    // ACTIVE: RAS=0 CAS=1 WE=1
    if (!sdram_cs_n && !sdram_ras_n && sdram_cas_n && sdram_we_n) begin
        if (expect_phase == 1) begin
            if (sdram_ba !== expect_bank || sdram_addr !== {1'b0, expect_row}) begin
                $display("FAIL: ACT address mismatch, got bank=%b row=%h exp bank=%b row=%h",
                         sdram_ba, sdram_addr[11:0], expect_bank, expect_row);
                $finish;
            end
            expect_phase <= 2;
        end
        row_open <= 1'b1;
        open_ba  <= sdram_ba;
        open_row <= sdram_addr;
    end

    // PRECHARGE: RAS=0 CAS=1 WE=0
    if (!sdram_cs_n && !sdram_ras_n && sdram_cas_n && !sdram_we_n) begin
        row_open <= 1'b0;

        if (init_stage < 4) begin
            // 只允许 init_stage=0 时出现 init 首条 PRECHARGE ALL
            if (init_stage == 0) begin
                if (sdram_addr[10] !== 1'b1) begin
                    $display("FAIL: init PRECHARGE not ALL banks");
                    $finish;
                end
                init_stage <= 1;
            end else begin
                // init 尚未结束时又看到 PRE，视为顺序错误
                $display("FAIL: unexpected PRECHARGE during init, stage=%0d", init_stage);
                $finish;
            end
        end
    end

    // AUTO REFRESH: RAS=0 CAS=0 WE=1
    if (!sdram_cs_n && !sdram_ras_n && !sdram_cas_n && sdram_we_n) begin
        saw_refresh_cmd <= 1;
        refresh_seen <= refresh_seen + 1;

        if (init_stage < 4) begin
            if (init_stage == 1) begin
                init_stage <= 2;
            end else if (init_stage == 2) begin
                init_stage <= 3;
            end else begin
                $display("FAIL: init AUTO REFRESH order wrong, stage=%0d", init_stage);
                $finish;
            end
        end
    end

    // LOAD MODE: RAS=0 CAS=0 WE=0
    if (!sdram_cs_n && !sdram_ras_n && !sdram_cas_n && !sdram_we_n) begin
        if (init_stage < 4) begin
            if (init_stage == 3) begin
                init_stage <= 4;
            end else begin
                $display("FAIL: init LOAD MODE order wrong, stage=%0d", init_stage);
                $finish;
            end
        end
    end

    // WRITE: RAS=1 CAS=0 WE=0
    if (!sdram_cs_n && sdram_ras_n && !sdram_cas_n && !sdram_we_n) begin
        if (!row_open) begin
            $display("FAIL: WRITE without open row");
            $finish;
        end
        if (sdram_ba !== open_ba) begin
            $display("FAIL: WRITE bank mismatch, got=%b open=%b", sdram_ba, open_ba);
            $finish;
        end
        if (expect_phase == 2 || expect_phase == 3) begin
            if (!expect_is_write) begin
                $display("FAIL: saw WRITE but expected READ command");
                $finish;
            end
            if (sdram_ba !== expect_bank) begin
                $display("FAIL: WRITE bank mismatch against expected access, got=%b exp=%b",
                         sdram_ba, expect_bank);
                $finish;
            end
            if (expect_phase == 2 && sdram_addr[8:0] !== expect_col_lo) begin
                $display("FAIL: low-half WRITE column mismatch, got=%h exp=%h",
                         sdram_addr[8:0], expect_col_lo);
                $finish;
            end
            if (expect_phase == 3 && sdram_addr[8:0] !== expect_col_hi) begin
                $display("FAIL: high-half WRITE column mismatch, got=%h exp=%h",
                         sdram_addr[8:0], expect_col_hi);
                $finish;
            end
            if (expect_phase == 2) expect_phase <= 3;
            else expect_phase <= 0;
        end
        saw_write_cmd <= 1;
        // apply DQM byte-mask
        if (dq_oe !== 1'b1) begin
            $display("FAIL: dq_oe not asserted during WRITE");
            $finish;
        end
        // key uses lower col bits only for this simple TB model
        if (!sdram_dqm[0]) mem[mk_addr_key(sdram_ba, {5'd0,sdram_addr[8:0]})][7:0]   <= dq_out[7:0];
        if (!sdram_dqm[1]) mem[mk_addr_key(sdram_ba, {5'd0,sdram_addr[8:0]})][15:8]  <= dq_out[15:8];
    end

    // READ: RAS=1 CAS=0 WE=1
    if (!sdram_cs_n && sdram_ras_n && !sdram_cas_n && sdram_we_n) begin
        if (!row_open) begin
            $display("FAIL: READ without open row");
            $finish;
        end
        if (sdram_ba !== open_ba) begin
            $display("FAIL: READ bank mismatch, got=%b open=%b", sdram_ba, open_ba);
            $finish;
        end
        if (expect_phase == 2 || expect_phase == 3) begin
            if (expect_is_write) begin
                $display("FAIL: saw READ but expected WRITE command");
                $finish;
            end
            if (sdram_ba !== expect_bank) begin
                $display("FAIL: READ bank mismatch against expected access, got=%b exp=%b",
                         sdram_ba, expect_bank);
                $finish;
            end
            if (expect_phase == 2 && sdram_addr[8:0] !== expect_col_lo) begin
                $display("FAIL: low-half READ column mismatch, got=%h exp=%h",
                         sdram_addr[8:0], expect_col_lo);
                $finish;
            end
            if (expect_phase == 3 && sdram_addr[8:0] !== expect_col_hi) begin
                $display("FAIL: high-half READ column mismatch, got=%h exp=%h",
                         sdram_addr[8:0], expect_col_hi);
                $finish;
            end
            if (expect_phase == 2) expect_phase <= 3;
            else expect_phase <= 0;
        end
        saw_read_cmd <= 1;
        if (dq_oe !== 1'b0) begin
            $display("FAIL: dq_oe asserted during READ");
            $finish;
        end
        read_data_latch <= mem[mk_addr_key(sdram_ba, {5'd0,sdram_addr[8:0]})];
        read_wait <= CAS_LATENCY_CYCLES;
        read_pending <= 1'b1;
    end
    end
end
initial begin
    #12000; // 覆盖二次初始化与 reset 恢复测试
    $display("TIMEOUT: DUT not ready, state=%0d", dut.dbg_state);
    $finish;
end

endmodule
