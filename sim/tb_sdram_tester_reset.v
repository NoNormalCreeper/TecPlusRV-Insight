// sdram_tester_ctrl 的复位重复运行仿真。
// 连续 3 次 reset/release 后都应完成同样的 PASS 收敛。
`timescale 1ns/1ps

module tb_sdram_tester_reset;

localparam integer TEST_WORDS = 4;
localparam integer PATTERN_COUNT = 4;

reg clk;
reg reset;
reg [3:0] reset_hold;
reg [1:0] pass_events;
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

initial begin
    clk = 1'b0;
    reset = 1'b1;
    reset_hold = 4'd4;
    pass_events = 2'd0;
    dq_in = 16'h0000;
    read_armed = 1'b0;
    read_wait = 4'd0;
    read_col = 10'd0;

    for (i = 0; i < 1024; i = i + 1) begin
        mem[i] = 16'hxxxx;
    end

    $dumpfile("sim/build/tb_sdram_tester_reset.vcd");
    $dumpvars(0, tb_sdram_tester_reset);

    #80000;
    $display("TIMEOUT: sdram_tester_reset 没有完成 3 次 reset/pass");
    $finish;
end

always @(posedge clk) begin
    if (reset) begin
        dq_in <= 16'h0000;
        read_armed <= 1'b0;
        read_wait <= 4'd0;
        read_col <= 10'd0;
        if (reset_hold == 4'd0) begin
            reset <= 1'b0;
        end else begin
            reset_hold <= reset_hold - 4'd1;
        end
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
            if (!dq_oe || sdram_addr[10] !== 1'b1) begin
                $display("FAIL: WRITE 周期方向或 auto-precharge 错误");
                $finish;
            end
            mem[sdram_addr[9:0]] <= dq_out;
        end

        if (!sdram_cs_n && sdram_ras_n && !sdram_cas_n && sdram_we_n) begin
            if (dq_oe || sdram_addr[10] !== 1'b1) begin
                $display("FAIL: READ 周期方向或 auto-precharge 错误");
                $finish;
            end
            read_col <= sdram_addr[9:0];
            read_wait <= 4'd0;
            read_armed <= 1'b1;
        end

        if (done_fail) begin
            $display("FAIL: reset 重复运行期间不应返回 FAIL");
            $finish;
        end

        if (done_pass) begin
            if (status_led !== 4'b1000 || error_count !== 16'd0 ||
                first_error_index !== 10'd0 || first_error_pattern !== 8'd0 ||
                first_error_expected !== 16'd0 || first_error_actual !== 16'd0) begin
                $display("FAIL: reset 后 PASS 状态或错误锁存不正确");
                $finish;
            end

            if (pass_events == 2'd2) begin
                $display("PASS: sdram_tester_reset 连续 3 次 reset 后稳定通过");
                $finish;
            end

            pass_events <= pass_events + 2'd1;
            reset <= 1'b1;
            reset_hold <= 4'd4;
        end
    end
end

endmodule
