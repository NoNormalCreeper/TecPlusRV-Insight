// M2a 板级 probe 的 UART 报告器。
// PASS 只输出 case id 和补充 info；FAIL 再带 step / err / info / exp / act。
module sdram_data_ctrl_probe_reporter (
    input         clk,
    input         reset,
    input         report_valid,
    input         report_fail,
    input  [7:0]  report_case_id,
    input  [7:0]  report_step_id,
    input  [7:0]  report_error_code,
    input  [31:0] report_info,
    input  [31:0] report_expected,
    input  [31:0] report_actual,
    input         tx_ready,
    output reg    tx_valid,
    output reg [7:0] tx_data,
    output reg    busy
);

localparam [7:0] PASS_LEN = 8'd22;
localparam [7:0] FAIL_LEN = 8'd54;

reg [7:0]  msg_index;
reg        latched_fail;
reg [7:0]  latched_case_id;
reg [7:0]  latched_step_id;
reg [7:0]  latched_error_code;
reg [31:0] latched_info;
reg [31:0] latched_expected;
reg [31:0] latched_actual;

wire [7:0] msg_len;

assign msg_len = latched_fail ? FAIL_LEN : PASS_LEN;

function [7:0] hex_digit;
    input [3:0] value;
    begin
        if (value < 4'd10) begin
            hex_digit = "0" + value;
        end else begin
            hex_digit = "a" + (value - 4'd10);
        end
    end
endfunction

function [7:0] byte_hex32;
    input [31:0] value;
    input [2:0] nibble_index;
    begin
        case (nibble_index)
            3'd0: byte_hex32 = hex_digit(value[31:28]);
            3'd1: byte_hex32 = hex_digit(value[27:24]);
            3'd2: byte_hex32 = hex_digit(value[23:20]);
            3'd3: byte_hex32 = hex_digit(value[19:16]);
            3'd4: byte_hex32 = hex_digit(value[15:12]);
            3'd5: byte_hex32 = hex_digit(value[11:8]);
            3'd6: byte_hex32 = hex_digit(value[7:4]);
            default: byte_hex32 = hex_digit(value[3:0]);
        endcase
    end
endfunction

function [7:0] message_byte;
    input [7:0] index;
    begin
        if (!latched_fail) begin
            case (index)
                8'd0:  message_byte = "P";
                8'd1:  message_byte = "A";
                8'd2:  message_byte = "S";
                8'd3:  message_byte = "S";
                8'd4:  message_byte = " ";
                8'd5:  message_byte = "c";
                8'd6:  message_byte = "=";
                8'd7:  message_byte = hex_digit(latched_case_id[7:4]);
                8'd8:  message_byte = hex_digit(latched_case_id[3:0]);
                8'd9:  message_byte = " ";
                8'd10: message_byte = "i";
                8'd11: message_byte = "=";
                8'd12: message_byte = byte_hex32(latched_info, 3'd0);
                8'd13: message_byte = byte_hex32(latched_info, 3'd1);
                8'd14: message_byte = byte_hex32(latched_info, 3'd2);
                8'd15: message_byte = byte_hex32(latched_info, 3'd3);
                8'd16: message_byte = byte_hex32(latched_info, 3'd4);
                8'd17: message_byte = byte_hex32(latched_info, 3'd5);
                8'd18: message_byte = byte_hex32(latched_info, 3'd6);
                8'd19: message_byte = byte_hex32(latched_info, 3'd7);
                8'd20: message_byte = 8'h0d;
                default: message_byte = 8'h0a;
            endcase
        end else begin
            case (index)
                8'd0:  message_byte = "F";
                8'd1:  message_byte = "A";
                8'd2:  message_byte = "I";
                8'd3:  message_byte = "L";
                8'd4:  message_byte = " ";
                8'd5:  message_byte = "c";
                8'd6:  message_byte = "=";
                8'd7:  message_byte = hex_digit(latched_case_id[7:4]);
                8'd8:  message_byte = hex_digit(latched_case_id[3:0]);
                8'd9:  message_byte = " ";
                8'd10: message_byte = "s";
                8'd11: message_byte = "=";
                8'd12: message_byte = hex_digit(latched_step_id[7:4]);
                8'd13: message_byte = hex_digit(latched_step_id[3:0]);
                8'd14: message_byte = " ";
                8'd15: message_byte = "e";
                8'd16: message_byte = "=";
                8'd17: message_byte = hex_digit(latched_error_code[7:4]);
                8'd18: message_byte = hex_digit(latched_error_code[3:0]);
                8'd19: message_byte = " ";
                8'd20: message_byte = "i";
                8'd21: message_byte = "=";
                8'd22: message_byte = byte_hex32(latched_info, 3'd0);
                8'd23: message_byte = byte_hex32(latched_info, 3'd1);
                8'd24: message_byte = byte_hex32(latched_info, 3'd2);
                8'd25: message_byte = byte_hex32(latched_info, 3'd3);
                8'd26: message_byte = byte_hex32(latched_info, 3'd4);
                8'd27: message_byte = byte_hex32(latched_info, 3'd5);
                8'd28: message_byte = byte_hex32(latched_info, 3'd6);
                8'd29: message_byte = byte_hex32(latched_info, 3'd7);
                8'd30: message_byte = " ";
                8'd31: message_byte = "x";
                8'd32: message_byte = "=";
                8'd33: message_byte = byte_hex32(latched_expected, 3'd0);
                8'd34: message_byte = byte_hex32(latched_expected, 3'd1);
                8'd35: message_byte = byte_hex32(latched_expected, 3'd2);
                8'd36: message_byte = byte_hex32(latched_expected, 3'd3);
                8'd37: message_byte = byte_hex32(latched_expected, 3'd4);
                8'd38: message_byte = byte_hex32(latched_expected, 3'd5);
                8'd39: message_byte = byte_hex32(latched_expected, 3'd6);
                8'd40: message_byte = byte_hex32(latched_expected, 3'd7);
                8'd41: message_byte = " ";
                8'd42: message_byte = "a";
                8'd43: message_byte = "=";
                8'd44: message_byte = byte_hex32(latched_actual, 3'd0);
                8'd45: message_byte = byte_hex32(latched_actual, 3'd1);
                8'd46: message_byte = byte_hex32(latched_actual, 3'd2);
                8'd47: message_byte = byte_hex32(latched_actual, 3'd3);
                8'd48: message_byte = byte_hex32(latched_actual, 3'd4);
                8'd49: message_byte = byte_hex32(latched_actual, 3'd5);
                8'd50: message_byte = byte_hex32(latched_actual, 3'd6);
                8'd51: message_byte = byte_hex32(latched_actual, 3'd7);
                8'd52: message_byte = 8'h0d;
                default: message_byte = 8'h0a;
            endcase
        end
    end
endfunction

always @(posedge clk) begin
    if (reset) begin
        msg_index <= 8'd0;
        latched_fail <= 1'b0;
        latched_case_id <= 8'd0;
        latched_step_id <= 8'd0;
        latched_error_code <= 8'd0;
        latched_info <= 32'd0;
        latched_expected <= 32'd0;
        latched_actual <= 32'd0;
        tx_valid <= 1'b0;
        tx_data <= 8'd0;
        busy <= 1'b0;
    end else begin
        if (tx_valid && tx_ready) begin
            tx_valid <= 1'b0;
            if (msg_index >= msg_len - 1) begin
                busy <= 1'b0;
                msg_index <= 8'd0;
            end else begin
                msg_index <= msg_index + 8'd1;
            end
        end else if (!busy && report_valid) begin
            busy <= 1'b1;
            msg_index <= 8'd0;
            latched_fail <= report_fail;
            latched_case_id <= report_case_id;
            latched_step_id <= report_step_id;
            latched_error_code <= report_error_code;
            latched_info <= report_info;
            latched_expected <= report_expected;
            latched_actual <= report_actual;
        end else if (busy && !tx_valid) begin
            tx_data <= message_byte(msg_index);
            tx_valid <= 1'b1;
        end
    end
end

endmodule
