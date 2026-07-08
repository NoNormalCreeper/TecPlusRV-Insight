// sdram_tester_uart_reporter 的格式化单元测试。
`timescale 1ns/1ps

module tb_sdram_tester_uart_reporter;

reg clk;
reg reset;
reg report_valid;
reg report_fail;
reg tx_ready;
reg [15:0] error_count;
reg [9:0]  first_error_index;
reg [7:0]  first_error_pattern;
reg [15:0] first_error_expected;
reg [15:0] first_error_actual;

wire tx_valid;
wire [7:0] tx_data;
wire busy;

integer byte_index;

sdram_tester_uart_reporter dut (
    .clk(clk),
    .reset(reset),
    .report_valid(report_valid),
    .report_fail(report_fail),
    .error_count(error_count),
    .first_error_index(first_error_index),
    .first_error_pattern(first_error_pattern),
    .first_error_expected(first_error_expected),
    .first_error_actual(first_error_actual),
    .tx_ready(tx_ready),
    .tx_valid(tx_valid),
    .tx_data(tx_data),
    .busy(busy)
);

always #5 clk = ~clk;

function [7:0] expected_byte;
    input integer index;
    begin
        case (index)
            0: expected_byte = "F";
            1: expected_byte = "A";
            2: expected_byte = "I";
            3: expected_byte = "L";
            4: expected_byte = " ";
            5: expected_byte = "e";
            6: expected_byte = "r";
            7: expected_byte = "r";
            8: expected_byte = "=";
            9: expected_byte = "0";
            10: expected_byte = "0";
            11: expected_byte = "0";
            12: expected_byte = "1";
            13: expected_byte = " ";
            14: expected_byte = "i";
            15: expected_byte = "d";
            16: expected_byte = "x";
            17: expected_byte = "=";
            18: expected_byte = "0";
            19: expected_byte = "0";
            20: expected_byte = "3";
            21: expected_byte = " ";
            22: expected_byte = "p";
            23: expected_byte = "a";
            24: expected_byte = "t";
            25: expected_byte = "=";
            26: expected_byte = "0";
            27: expected_byte = "2";
            28: expected_byte = " ";
            29: expected_byte = "e";
            30: expected_byte = "x";
            31: expected_byte = "p";
            32: expected_byte = "=";
            33: expected_byte = "3";
            34: expected_byte = "c";
            35: expected_byte = "c";
            36: expected_byte = "3";
            37: expected_byte = " ";
            38: expected_byte = "a";
            39: expected_byte = "c";
            40: expected_byte = "t";
            41: expected_byte = "=";
            42: expected_byte = "3";
            43: expected_byte = "c";
            44: expected_byte = "c";
            45: expected_byte = "2";
            46: expected_byte = 8'h0d;
            default: expected_byte = 8'h0a;
        endcase
    end
endfunction

initial begin
    clk = 1'b0;
    reset = 1'b1;
    report_valid = 1'b0;
    report_fail = 1'b0;
    tx_ready = 1'b1;
    error_count = 16'h0001;
    first_error_index = 10'd3;
    first_error_pattern = 8'd2;
    first_error_expected = 16'h3cc3;
    first_error_actual = 16'h3cc2;
    byte_index = 0;

    #40;
    reset = 1'b0;
    #20;
    report_fail = 1'b1;
    report_valid = 1'b1;
    #10;
    report_valid = 1'b0;

    #2000;
    $display("TIMEOUT: sdram_tester_uart_reporter 没有完成");
    $finish;
end

always @(posedge clk) begin
    if (!reset && tx_valid && tx_ready) begin
        if (tx_data !== expected_byte(byte_index)) begin
            $display(
                "FAIL: UART reporter byte %0d expected=0x%02x actual=0x%02x",
                byte_index,
                expected_byte(byte_index),
                tx_data
            );
            $finish;
        end

        if (byte_index == 47) begin
            $display("PASS: sdram_tester_uart_reporter FAIL 消息格式正确");
            $finish;
        end

        byte_index = byte_index + 1;
    end
end

endmodule
