// sdram_tester_ctrl 的模块级仿真。
// 这里建一个很小的行为内存，只验证 tester 的多地址写读和 PASS/FAIL 控制流。
`timescale 1ns/1ps

module tb_sdram_tester_ctrl;

localparam integer TEST_WORDS = 8;

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
wire [9:0]  test_index;
wire [7:0]  pass_count;
wire        done_pass;
wire        done_fail;

reg [15:0] mem [0:1023];
reg        read_armed;
reg [3:0]  read_wait;
reg [9:0]  read_col;
integer    write_seen;
integer    read_seen;
integer    i;

sdram_tester_ctrl #(
    .PWRUP_WAIT_CYCLES(4),
    .TRP_CYCLES(2),
    .TRFC_CYCLES(2),
    .TMRD_CYCLES(2),
    .TRCD_CYCLES(2),
    .TWR_CYCLES(2),
    .CAS_LATENCY_CYCLES(2),
    .PASS_HOLD_CYCLES(4),
    .TEST_WORDS(TEST_WORDS)
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
    .test_index(test_index),
    .pass_count(pass_count),
    .done_pass(done_pass),
    .done_fail(done_fail)
);

always #5 clk = ~clk;

function [15:0] make_pattern;
    input [9:0] index;
    input [7:0] round;
    begin
        make_pattern = 16'hA55A ^ {index[7:0], index[9:2]} ^ {round, ~round};
    end
endfunction

initial begin
    clk = 1'b0;
    reset = 1'b1;
    dq_in = 16'h0000;
    read_armed = 1'b0;
    read_wait = 4'd0;
    read_col = 10'd0;
    write_seen = 0;
    read_seen = 0;

    for (i = 0; i < 1024; i = i + 1) begin
        mem[i] = 16'hxxxx;
    end

    $dumpfile("sim/build/tb_sdram_tester_ctrl.vcd");
    $dumpvars(0, tb_sdram_tester_ctrl);

    #40;
    reset = 1'b0;

    #20000;
    $display("TIMEOUT: sdram_tester_ctrl 没有完成");
    $finish;
end

always @(posedge clk) begin
    if (reset) begin
        dq_in <= 16'h0000;
        read_armed <= 1'b0;
        read_wait <= 4'd0;
        read_col <= 10'd0;
        write_seen <= 0;
        read_seen <= 0;
    end else begin
        if (read_armed) begin
            if (read_wait == 4'd0) begin
                dq_in <= mem[read_col];
                read_armed <= 1'b0;
            end else begin
                read_wait <= read_wait - 4'd1;
            end
        end

        if (!sdram_cs_n && sdram_ras_n && !sdram_cas_n && !sdram_we_n) begin
            if (!dq_oe) begin
                $display("FAIL: WRITE 周期没有驱动 DQ");
                $finish;
            end
            if (sdram_dqm !== 2'b00) begin
                $display("FAIL: WRITE 周期 DQM 没有打开");
                $finish;
            end
            if (sdram_addr[10] !== 1'b1) begin
                $display("FAIL: WRITE 没有使用 auto-precharge");
                $finish;
            end
            if (dq_out !== make_pattern(sdram_addr[9:0], pass_count)) begin
                $display("FAIL: WRITE pattern 错误 addr=%0d data=%h", sdram_addr[9:0], dq_out);
                $finish;
            end
            mem[sdram_addr[9:0]] <= dq_out;
            write_seen <= write_seen + 1;
        end

        if (!sdram_cs_n && sdram_ras_n && !sdram_cas_n && sdram_we_n) begin
            if (dq_oe) begin
                $display("FAIL: READ 周期不应驱动 DQ");
                $finish;
            end
            if (sdram_addr[10] !== 1'b1) begin
                $display("FAIL: READ 没有使用 auto-precharge");
                $finish;
            end
            read_col <= sdram_addr[9:0];
            read_wait <= 4'd0;
            read_armed <= 1'b1;
            read_seen <= read_seen + 1;
        end

        if (done_fail) begin
            $display("FAIL: sdram_tester_ctrl 返回 FAIL");
            $finish;
        end

        if (done_pass) begin
            if (write_seen !== TEST_WORDS) begin
                $display("FAIL: 写入数量不正确 writes=%0d", write_seen);
                $finish;
            end
            if (read_seen !== TEST_WORDS) begin
                $display("FAIL: 读取数量不正确 reads=%0d", read_seen);
                $finish;
            end
            if (status_led !== 4'b1000) begin
                $display("FAIL: PASS 状态 LED 不正确");
                $finish;
            end
            $display("PASS: sdram_tester_ctrl 多地址写读校验通过");
            $finish;
        end
    end
end

endmodule
