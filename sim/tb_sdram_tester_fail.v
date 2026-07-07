// sdram_tester_ctrl 的受控失败仿真。
// 行为内存在一个指定地址/pattern 上注入 1 bit 错误，期望 DUT 锁存首错并进入 FAIL。
`timescale 1ns/1ps

module tb_sdram_tester_fail;

localparam integer TEST_WORDS = 8;
localparam integer PATTERN_COUNT = 4;
localparam [9:0]  INJECT_INDEX = 10'd3;
localparam [7:0]  INJECT_PATTERN = 8'd2;

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
wire [7:0]  pattern_index;
wire [7:0]  pass_count;
wire [15:0] error_count;
wire [9:0]  first_error_index;
wire [7:0]  first_error_pattern;
wire [15:0] first_error_expected;
wire [15:0] first_error_actual;
wire        done_pass;
wire        done_fail;

reg [15:0] mem [0:1023];
reg        read_armed;
reg [3:0]  read_wait;
reg [9:0]  read_col;
reg [7:0]  read_pattern;
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
    .TEST_WORDS(TEST_WORDS),
    .PATTERN_COUNT(PATTERN_COUNT)
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

always #5 clk = ~clk;

function [15:0] make_pattern;
    input [9:0] index;
    input [7:0] pattern;
    input [7:0] round;
    begin
        case (pattern[1:0])
            2'd0: make_pattern = 16'hA55A ^ {index[7:0], index[9:2]} ^ {round, ~round};
            2'd1: make_pattern = 16'h5AA5 ^ {~index[7:0], index[9:2]} ^ {~round, round};
            2'd2: make_pattern = {index[7:0], ~index[7:0]} ^ {round, 8'h3C};
            default: make_pattern = {~index[7:0], index[7:0]} ^ {8'hC3, round};
        endcase
    end
endfunction

initial begin
    clk = 1'b0;
    reset = 1'b1;
    dq_in = 16'h0000;
    read_armed = 1'b0;
    read_wait = 4'd0;
    read_col = 10'd0;
    read_pattern = 8'd0;
    write_seen = 0;
    read_seen = 0;

    for (i = 0; i < 1024; i = i + 1) begin
        mem[i] = 16'hxxxx;
    end

    $dumpfile("sim/build/tb_sdram_tester_fail.vcd");
    $dumpvars(0, tb_sdram_tester_fail);

    #40;
    reset = 1'b0;

    #30000;
    $display("TIMEOUT: sdram_tester_fail 没有完成");
    $finish;
end

always @(posedge clk) begin
    if (reset) begin
        dq_in <= 16'h0000;
        read_armed <= 1'b0;
        read_wait <= 4'd0;
        read_col <= 10'd0;
        read_pattern <= 8'd0;
        write_seen <= 0;
        read_seen <= 0;
    end else begin
        if (read_armed) begin
            if (read_wait == 4'd0) begin
                if (read_col == INJECT_INDEX && read_pattern == INJECT_PATTERN) begin
                    dq_in <= mem[read_col] ^ 16'h0001;
                end else begin
                    dq_in <= mem[read_col];
                end
                read_armed <= 1'b0;
            end else begin
                read_wait <= read_wait - 4'd1;
            end
        end

        if (!sdram_cs_n && sdram_ras_n && !sdram_cas_n && !sdram_we_n) begin
            if (!dq_oe || sdram_addr[10] !== 1'b1) begin
                $display("FAIL: WRITE 周期方向或 auto-precharge 错误");
                $finish;
            end
            if (dq_out !== make_pattern(sdram_addr[9:0], pattern_index, pass_count)) begin
                $display("FAIL: WRITE pattern 错误 addr=%0d data=%h", sdram_addr[9:0], dq_out);
                $finish;
            end
            mem[sdram_addr[9:0]] <= dq_out;
            write_seen <= write_seen + 1;
        end

        if (!sdram_cs_n && sdram_ras_n && !sdram_cas_n && sdram_we_n) begin
            if (dq_oe || sdram_addr[10] !== 1'b1) begin
                $display("FAIL: READ 周期方向或 auto-precharge 错误");
                $finish;
            end
            read_col <= sdram_addr[9:0];
            read_pattern <= pattern_index;
            read_wait <= 4'd0;
            read_armed <= 1'b1;
            read_seen <= read_seen + 1;
        end

        if (done_pass) begin
            $display("FAIL: 注错路径不应返回 PASS");
            $finish;
        end

        if (done_fail) begin
            if (status_led !== 4'b1111) begin
                $display("FAIL: FAIL 状态 LED 不正确");
                $finish;
            end
            if (write_seen !== TEST_WORDS * PATTERN_COUNT ||
                read_seen !== TEST_WORDS * PATTERN_COUNT) begin
                $display("FAIL: 注错路径没有完成完整 sweep writes=%0d reads=%0d", write_seen, read_seen);
                $finish;
            end
            if (error_count !== 16'd1) begin
                $display("FAIL: 错误计数不正确 error_count=%0d", error_count);
                $finish;
            end
            if (first_error_index !== INJECT_INDEX ||
                first_error_pattern !== INJECT_PATTERN) begin
                $display(
                    "FAIL: 首错位置不正确 index=%0d pattern=%0d",
                    first_error_index,
                    first_error_pattern
                );
                $finish;
            end
            if (first_error_expected !== make_pattern(INJECT_INDEX, INJECT_PATTERN, 8'd0) ||
                first_error_actual !== (make_pattern(INJECT_INDEX, INJECT_PATTERN, 8'd0) ^ 16'h0001)) begin
                $display(
                    "FAIL: 首错数据不正确 expected=%h actual=%h",
                    first_error_expected,
                    first_error_actual
                );
                $finish;
            end
            $display("PASS: sdram_tester_fail 受控注错被正确锁存");
            $finish;
        end
    end
end

endmodule
