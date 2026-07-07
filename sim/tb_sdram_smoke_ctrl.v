// sdram_smoke_ctrl 的命令序列仿真。
// testbench 不建完整 SDRAM 模型，只检查命令顺序，并在 READ 后喂回 TEST_DATA。
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
reg [3:0]  cycles_after_write_ap;
reg        write_ap_pending;

sdram_smoke_ctrl #(
    // 把真实等待周期缩短，保持状态机顺序不变但让仿真快速结束。
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
    cycles_after_write_ap = 4'd0;
    write_ap_pending = 1'b0;

    $dumpfile("sim/build/tb_sdram_smoke_ctrl.vcd");
    $dumpvars(0, tb_sdram_smoke_ctrl);

    #40;
    reset = 1'b0;

    #4000;
    $display("TIMEOUT: sdram_smoke_ctrl 没有完成");
    $finish;
end

always @(posedge clk) begin
    if (write_ap_pending) begin
        cycles_after_write_ap <= cycles_after_write_ap + 4'd1;
    end

    if (read_armed) begin
        if (read_wait == 4'd0) begin
            // 模拟 SDRAM 在 CAS latency 后把写入的数据读回来。
            dq_in <= 16'hA55A;
            read_armed <= 1'b0;
        end else begin
            read_wait <= read_wait - 4'd1;
        end
    end

    if (!sdram_cs_n && !sdram_ras_n && sdram_cas_n && !sdram_we_n) begin
        // RAS=0 CAS=1 WE=0 是 PRECHARGE；A10=1 表示 all banks。
        if (sdram_addr[10] !== 1'b1 || seen_stage !== 4'd0) begin
            $display("FAIL: PRECHARGE ALL 顺序错误");
            $finish;
        end
        seen_stage <= 4'd1;
    end

    if (!sdram_cs_n && !sdram_ras_n && !sdram_cas_n && sdram_we_n) begin
        // RAS=0 CAS=0 WE=1 是 AUTO REFRESH。
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
        // RAS=0 CAS=0 WE=0 是 LOAD MODE REGISTER。
        if (seen_stage !== 4'd3) begin
            $display("FAIL: LOAD MODE 顺序错误");
            $finish;
        end
        seen_stage <= 4'd4;
    end

    if (!sdram_cs_n && !sdram_ras_n && sdram_cas_n && sdram_we_n) begin
        // RAS=0 CAS=1 WE=1 是 ACTIVE，用于打开 row。
        if (write_ap_pending) begin
            // WRITE 用了 auto-precharge，因此再次 ACT 前至少还要等完 tWR+tRP。
            if (cycles_after_write_ap < 4) begin
                $display("FAIL: WRITE(auto-precharge) 后过早再次 ACT");
                $finish;
            end
            write_ap_pending <= 1'b0;
        end
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
        // RAS=1 CAS=0 WE=0 是 WRITE。
        if (seen_stage !== 4'd5) begin
            $display("FAIL: WRITE 顺序错误");
            $finish;
        end
        if (sdram_addr[10] !== 1'b1) begin
            $display("FAIL: 当前 smoke probe 预期 WRITE 使用 auto-precharge");
            $finish;
        end
        if (!dq_oe || dq_out !== 16'hA55A) begin
            $display("FAIL: WRITE 数据或方向错误");
            $finish;
        end
        cycles_after_write_ap <= 4'd0;
        write_ap_pending <= 1'b1;
        seen_stage <= 4'd6;
    end

    if (!sdram_cs_n && sdram_ras_n && !sdram_cas_n && sdram_we_n) begin
        // RAS=1 CAS=0 WE=1 是 READ。
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
