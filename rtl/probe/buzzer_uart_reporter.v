// 蜂鸣器 Probe 的 UART 文本报告器。
// 每次切换到新音符时，发一个很短的 token，方便把“听到的节奏”和“RTL 以为自己在播的内容”对上。
// 当前 token 顺序固定为：
//   3
//   2_
//   1
//   2_
//   3_
//   4__
//   3_
//   2-
module buzzer_uart_reporter (
    input clk,
    input reset,
    input note_event,
    input [2:0] event_note_index,
    input tx_ready,
    output reg tx_valid,
    output reg [7:0] tx_data,
    output reg busy
);

reg [2:0] latched_note_index;
reg [2:0] msg_index;

function [2:0] token_len;
    input [2:0] note_index;
    begin
        case (note_index)
            3'd0: token_len = 3'd3; // 3\r\n
            3'd1: token_len = 3'd4; // 2_\r\n
            3'd2: token_len = 3'd3; // 1\r\n
            3'd3: token_len = 3'd4; // 2_\r\n
            3'd4: token_len = 3'd4; // 3_\r\n
            3'd5: token_len = 3'd5; // 4__\r\n
            3'd6: token_len = 3'd4; // 3_\r\n
            default: token_len = 3'd4; // 2-\r\n
        endcase
    end
endfunction

function [7:0] token_byte;
    input [2:0] note_index;
    input [2:0] byte_index;
    begin
        case (note_index)
            3'd0: begin
                case (byte_index)
                    3'd0: token_byte = "3";
                    3'd1: token_byte = 8'h0d;
                    default: token_byte = 8'h0a;
                endcase
            end
            3'd1: begin
                case (byte_index)
                    3'd0: token_byte = "2";
                    3'd1: token_byte = "_";
                    3'd2: token_byte = 8'h0d;
                    default: token_byte = 8'h0a;
                endcase
            end
            3'd2: begin
                case (byte_index)
                    3'd0: token_byte = "1";
                    3'd1: token_byte = 8'h0d;
                    default: token_byte = 8'h0a;
                endcase
            end
            3'd3: begin
                case (byte_index)
                    3'd0: token_byte = "2";
                    3'd1: token_byte = "_";
                    3'd2: token_byte = 8'h0d;
                    default: token_byte = 8'h0a;
                endcase
            end
            3'd4: begin
                case (byte_index)
                    3'd0: token_byte = "3";
                    3'd1: token_byte = "_";
                    3'd2: token_byte = 8'h0d;
                    default: token_byte = 8'h0a;
                endcase
            end
            3'd5: begin
                case (byte_index)
                    3'd0: token_byte = "4";
                    3'd1: token_byte = "_";
                    3'd2: token_byte = "_";
                    3'd3: token_byte = 8'h0d;
                    default: token_byte = 8'h0a;
                endcase
            end
            3'd6: begin
                case (byte_index)
                    3'd0: token_byte = "3";
                    3'd1: token_byte = "_";
                    3'd2: token_byte = 8'h0d;
                    default: token_byte = 8'h0a;
                endcase
            end
            default: begin
                case (byte_index)
                    3'd0: token_byte = "2";
                    3'd1: token_byte = "-";
                    3'd2: token_byte = 8'h0d;
                    default: token_byte = 8'h0a;
                endcase
            end
        endcase
    end
endfunction

always @(posedge clk) begin
    if (reset) begin
        latched_note_index <= 3'd0;
        msg_index <= 3'd0;
        tx_valid <= 1'b0;
        tx_data <= 8'd0;
        busy <= 1'b0;
    end else begin
        if (tx_valid && tx_ready) begin
            tx_valid <= 1'b0;
            if (msg_index >= token_len(latched_note_index) - 1) begin
                busy <= 1'b0;
                msg_index <= 3'd0;
            end else begin
                msg_index <= msg_index + 3'd1;
            end
        end else if (!busy && note_event) begin
            busy <= 1'b1;
            msg_index <= 3'd0;
            latched_note_index <= event_note_index;
        end else if (busy && !tx_valid) begin
            tx_data <= token_byte(latched_note_index, msg_index);
            tx_valid <= 1'b1;
        end
    end
end

endmodule
