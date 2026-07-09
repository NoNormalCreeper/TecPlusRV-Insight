// sdram_data_ctrl_probe_reporter 的 FAIL 消息单测。
`timescale 1ns/1ps

module tb_sdram_data_ctrl_probe_reporter;

reg clk;
reg reset;
reg report_valid;
reg report_fail;
reg tx_ready;
reg [7:0]  report_case_id;
reg [7:0]  report_step_id;
reg [7:0]  report_error_code;
reg [31:0] report_info;
reg [31:0] report_expected;
reg [31:0] report_actual;

wire tx_valid;
wire [7:0] tx_data;
wire busy;

integer byte_index;

sdram_data_ctrl_probe_reporter dut (
    .clk(clk),
    .reset(reset),
    .report_valid(report_valid),
    .report_fail(report_fail),
    .report_case_id(report_case_id),
    .report_step_id(report_step_id),
    .report_error_code(report_error_code),
    .report_info(report_info),
    .report_expected(report_expected),
    .report_actual(report_actual),
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
            5: expected_byte = "c";
            6: expected_byte = "=";
            7: expected_byte = "0";
            8: expected_byte = "7";
            9: expected_byte = " ";
            10: expected_byte = "s";
            11: expected_byte = "=";
            12: expected_byte = "0";
            13: expected_byte = "2";
            14: expected_byte = " ";
            15: expected_byte = "e";
            16: expected_byte = "=";
            17: expected_byte = "0";
            18: expected_byte = "4";
            19: expected_byte = " ";
            20: expected_byte = "i";
            21: expected_byte = "=";
            22: expected_byte = "0";
            23: expected_byte = "0";
            24: expected_byte = "1";
            25: expected_byte = "2";
            26: expected_byte = "0";
            27: expected_byte = "4";
            28: expected_byte = "4";
            29: expected_byte = "0";
            30: expected_byte = " ";
            31: expected_byte = "x";
            32: expected_byte = "=";
            33: expected_byte = "c";
            34: expected_byte = "a";
            35: expected_byte = "f";
            36: expected_byte = "e";
            37: expected_byte = "b";
            38: expected_byte = "a";
            39: expected_byte = "b";
            40: expected_byte = "e";
            41: expected_byte = " ";
            42: expected_byte = "a";
            43: expected_byte = "=";
            44: expected_byte = "d";
            45: expected_byte = "e";
            46: expected_byte = "a";
            47: expected_byte = "d";
            48: expected_byte = "b";
            49: expected_byte = "e";
            50: expected_byte = "e";
            51: expected_byte = "f";
            52: expected_byte = 8'h0d;
            default: expected_byte = 8'h0a;
        endcase
    end
endfunction

initial begin
    clk = 1'b0;
    reset = 1'b1;
    report_valid = 1'b0;
    report_fail = 1'b1;
    tx_ready = 1'b1;
    report_case_id = 8'h07;
    report_step_id = 8'h02;
    report_error_code = 8'h04;
    report_info = 32'h0012_0440;
    report_expected = 32'hcafe_babe;
    report_actual = 32'hdead_beef;
    byte_index = 0;

    #40;
    reset = 1'b0;
    #20;
    report_valid = 1'b1;
    #10;
    report_valid = 1'b0;

    #3000;
    $display("TIMEOUT: sdram_data_ctrl_probe_reporter 没有完成");
    $finish;
end

always @(posedge clk) begin
    if (!reset && tx_valid && tx_ready) begin
        if (tx_data !== expected_byte(byte_index)) begin
            $display("FAIL: reporter byte %0d expected=0x%02x actual=0x%02x",
                byte_index, expected_byte(byte_index), tx_data);
            $finish;
        end

        if (byte_index == 53) begin
            $display("PASS: sdram_data_ctrl_probe_reporter FAIL 消息格式正确");
            $finish;
        end

        byte_index = byte_index + 1;
    end
end

endmodule
