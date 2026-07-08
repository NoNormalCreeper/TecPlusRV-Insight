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
    row_open = 1'b0;
    open_ba = 2'b00;
    open_row = 13'd0;

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

    // 4) misaligned access should error
    host_read32(32'h0000_0042);
    if (!resp_err) begin
        $display("FAIL: misaligned read did not raise resp_err");
        $finish;
    end
    saw_misaligned_resp = 1;

    // 5) wait to observe at least one refresh command after idle
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
    req_addr  <= addr;
    req_wdata <= data;
    req_wstrb <= wstrb;
    req_we    <= 1'b1;
    req_valid <= 1'b1;
    @(posedge clk);
    req_valid <= 1'b0;
    req_we    <= 1'b0;
    req_wstrb <= 4'b0000;
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
    req_addr  <= addr;
    req_wdata <= 32'd0;
    req_wstrb <= 4'b0000;
    req_we    <= 1'b0;
    req_valid <= 1'b1;
    @(posedge clk);
    req_valid <= 1'b0;
    wait(resp_valid);
    @(posedge clk);
end
endtask

// decode/observe SDRAM commands and emulate read data latency
always @(posedge clk) begin
    cycles <= cycles + 1;

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
        row_open <= 1'b1;
        open_ba  <= sdram_ba;
        open_row <= sdram_addr;
    end

    // PRECHARGE: RAS=0 CAS=1 WE=0
    if (!sdram_cs_n && !sdram_ras_n && sdram_cas_n && !sdram_we_n) begin
        row_open <= 1'b0;
        // init sequence expects first PRECHARGE ALL then ARx2 then MRS
        if (init_stage == 0) begin
            if (sdram_addr[10] !== 1'b1) begin
                $display("FAIL: init PRECHARGE not ALL banks");
                $finish;
            end
            init_stage <= 1;
        end
    end

    // AUTO REFRESH: RAS=0 CAS=0 WE=1
    if (!sdram_cs_n && !sdram_ras_n && !sdram_cas_n && sdram_we_n) begin
        saw_refresh_cmd <= 1;
        refresh_seen <= refresh_seen + 1;
        if (init_stage == 1) init_stage <= 2;
        else if (init_stage == 2) init_stage <= 3;
    end

    // LOAD MODE: RAS=0 CAS=0 WE=0
    if (!sdram_cs_n && !sdram_ras_n && !sdram_cas_n && !sdram_we_n) begin
        if (init_stage == 3) init_stage <= 4;
    end

    // WRITE: RAS=1 CAS=0 WE=0
    if (!sdram_cs_n && sdram_ras_n && !sdram_cas_n && !sdram_we_n) begin
        if (!row_open) begin
            $display("FAIL: WRITE without open row");
            $finish;
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

endmodule