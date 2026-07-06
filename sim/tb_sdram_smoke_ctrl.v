`timescale 1ns/1ps

module tb_sdram_smoke_ctrl;

reg clk;
reg reset;
reg [15:0] dq_in;

wire        dq_oe;
wire [15:0] dq_out;
wire        sdram_cke;
wire        sdram_cs_n;
wire        sdram_ras_n;
wire        sdram_cas_n;
wire        sdram_we_n;
wire [1:0]  sdram_ba;
wire [12:0] sdram_addr;
wire [1:0]  sdram_dqm;
wire [3:0]  status_led;
wire        done_pass;
wire        done_fail;

reg [3:0]  seen_stage;
reg [3:0]  read_wait;
reg        read_armed;

sdram_smoke_ctrl #(
    .PWRUP_WAIT_CYCLES(4),
    .TRP_CYCLES(2),
    .TRFC_CYCLES(2),
    .TMRD_CYCLES(2),
    .TRCD_CYCLES(2),
    .TWR_CYCLES(2),
    .CAS_LATENCY_CYCLES(2),
    .TEST_DATA(16'hA55A)
) dut (
    .clk(clk),
    .reset(reset),
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
    .status_led(status_led),
    .done_pass(done_pass),
    .done_fail(done_fail)
);

always #5 clk = ~clk;

`ifdef DEBUG
always @(posedge clk) begin
    $display(
        "DBG t=%0t state=%0d wait=%0d stage=%0d dq_in=%h pass=%b fail=%b cmd=%b%b%b%b",
        $time,
        dut.state,
        dut.wait_count,
        seen_stage,
        dq_in,
        done_pass,
        done_fail,
        sdram_cs_n,
        sdram_ras_n,
        sdram_cas_n,
        sdram_we_n
    );
end
`endif

initial begin
    clk = 1'b0;
    reset = 1'b1;
    dq_in = 16'h0000;
    seen_stage = 4'd0;
    read_wait = 4'd0;
    read_armed = 1'b0;

    $dumpfile("sim/build/tb_sdram_smoke_ctrl.vcd");
    $dumpvars(0, tb_sdram_smoke_ctrl);

    #40;
    reset = 1'b0;

    #4000;
    $display("TIMEOUT: sdram_smoke_ctrl 没有完成");
    $finish;
end

always @(posedge clk) begin
    if (read_armed) begin
        if (read_wait == 4'd0) begin
            dq_in <= 16'hA55A;
            read_armed <= 1'b0;
        end else begin
            read_wait <= read_wait - 4'd1;
        end
    end

    if (!sdram_cs_n && !sdram_ras_n && sdram_cas_n && !sdram_we_n) begin
        if (sdram_addr[10] !== 1'b1 || seen_stage !== 4'd0) begin
            $display("FAIL: PRECHARGE ALL 顺序错误");
            $finish;
        end
        seen_stage <= 4'd1;
    end

    if (!sdram_cs_n && !sdram_ras_n && !sdram_cas_n && sdram_we_n) begin
        if (seen_stage == 4'd1) begin
            seen_stage <= 4'd2;
        end else if (seen_stage == 4'd2) begin
            seen_stage <= 4'd3;
        end else begin
            $display("FAIL: AUTO REFRESH 顺序错误");
            $finish;
        end
    end

    if (!sdram_cs_n && !sdram_ras_n && !sdram_cas_n && !sdram_we_n) begin
        if (seen_stage !== 4'd3) begin
            $display("FAIL: LOAD MODE 顺序错误");
            $finish;
        end
        seen_stage <= 4'd4;
    end

    if (!sdram_cs_n && !sdram_ras_n && sdram_cas_n && sdram_we_n) begin
        if (seen_stage == 4'd4) begin
            seen_stage <= 4'd5;
        end else if (seen_stage == 4'd6) begin
            seen_stage <= 4'd7;
        end else begin
            $display("FAIL: ACTIVE 顺序错误");
            $finish;
        end
    end

    if (!sdram_cs_n && sdram_ras_n && !sdram_cas_n && !sdram_we_n) begin
        if (seen_stage !== 4'd5) begin
            $display("FAIL: WRITE 顺序错误");
            $finish;
        end
        if (!dq_oe || dq_out !== 16'hA55A) begin
            $display("FAIL: WRITE 数据或方向错误");
            $finish;
        end
        seen_stage <= 4'd6;
    end

    if (!sdram_cs_n && sdram_ras_n && !sdram_cas_n && sdram_we_n) begin
        if (seen_stage !== 4'd7) begin
            $display("FAIL: READ 顺序错误");
            $finish;
        end
        seen_stage <= 4'd8;
        read_wait <= 4'd0;
        read_armed <= 1'b1;
    end

    if (done_fail) begin
        $display("FAIL: sdram_smoke_ctrl 返回 FAIL");
        $finish;
    end

    if (done_pass) begin
        if (seen_stage !== 4'd8) begin
            $display("FAIL: 完成前命令序列不完整");
            $finish;
        end
        if (status_led !== 4'b1000) begin
            $display("FAIL: PASS 状态 LED 不正确");
            $finish;
        end
        $display("PASS: sdram_smoke_ctrl 命令序列与读回比较通过");
        $finish;
    end
end

endmodule
