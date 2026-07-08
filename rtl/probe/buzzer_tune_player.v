// 蜂鸣器短句播放器。
// 当前只服务于 Probe 5c，循环播放用户指定的固定旋律：
//   3 2_ 1 2_ 3_ 4__ 3_ 2-
//
// 这里采用的近似规则需要明确写清：
// - 调号按 `1 = B`，并统一使用高音区，所以 1/2/3/4 对应 B5/C#6/D#6/E6。
// - 节拍按 6/8 处理，但这里只拿“1 拍”的时长参数化，不再引入更复杂的强弱拍。
// - 裸数字记为 1 拍，`_` 记为半拍，`__` 记为 1/4 拍。
// - `-` 记为额外延长 1 拍，所以 `2-` 总时长按 2 拍处理。
module buzzer_tune_player #(
    parameter integer CLK_FREQ = 50000000,
    parameter integer BEAT_TICKS = 25000000
) (
    input clk,
    input reset,
    output reg spk,
    output reg [2:0] current_note_index,
    output reg [2:0] event_note_index,
    output reg note_event
);

reg [31:0] duration_count;
reg [31:0] tone_count;
reg        start_pending;

function [31:0] note_half_period;
    input [2:0] index;
    begin
        case (index)
            3'd0: note_half_period = (CLK_FREQ + 1245) / 2490; // 3 = D#6 ≈ 1244.51 Hz
            3'd1: note_half_period = (CLK_FREQ + 1109) / 2218; // 2 = C#6 ≈ 1108.73 Hz
            3'd2: note_half_period = (CLK_FREQ + 988)  / 1976; // 1 = B5  ≈ 987.77 Hz
            3'd3: note_half_period = (CLK_FREQ + 1109) / 2218; // 2 = C#6
            3'd4: note_half_period = (CLK_FREQ + 1245) / 2490; // 3 = D#6
            3'd5: note_half_period = (CLK_FREQ + 1319) / 2638; // 4 = E6  ≈ 1318.51 Hz
            3'd6: note_half_period = (CLK_FREQ + 1245) / 2490; // 3 = D#6
            default: note_half_period = (CLK_FREQ + 1109) / 2218; // 2 = C#6
        endcase
    end
endfunction

function [31:0] note_duration_ticks;
    input [2:0] index;
    begin
        case (index)
            3'd0: note_duration_ticks = BEAT_TICKS;
            3'd1: note_duration_ticks = BEAT_TICKS / 2;
            3'd2: note_duration_ticks = BEAT_TICKS;
            3'd3: note_duration_ticks = BEAT_TICKS / 2;
            3'd4: note_duration_ticks = BEAT_TICKS / 2;
            3'd5: note_duration_ticks = BEAT_TICKS / 4;
            3'd6: note_duration_ticks = BEAT_TICKS / 2;
            default: note_duration_ticks = BEAT_TICKS * 2;
        endcase
    end
endfunction

function [2:0] next_note_index;
    input [2:0] index;
    begin
        if (index >= 3'd7) begin
            next_note_index = 3'd0;
        end else begin
            next_note_index = index + 3'd1;
        end
    end
endfunction

always @(posedge clk) begin
    if (reset) begin
        spk <= 1'b0;
        current_note_index <= 3'd0;
        event_note_index <= 3'd0;
        note_event <= 1'b0;
        duration_count <= 32'd0;
        tone_count <= 32'd0;
        start_pending <= 1'b1;
    end else begin
        note_event <= 1'b0;

        if (start_pending) begin
            start_pending <= 1'b0;
            spk <= 1'b0;
            duration_count <= 32'd0;
            tone_count <= 32'd0;
            event_note_index <= current_note_index;
            note_event <= 1'b1;
        end else begin
            if (tone_count >= note_half_period(current_note_index) - 1) begin
                tone_count <= 32'd0;
                spk <= !spk;
            end else begin
                tone_count <= tone_count + 32'd1;
            end

            if (duration_count >= note_duration_ticks(current_note_index) - 1) begin
                current_note_index <= next_note_index(current_note_index);
                event_note_index <= next_note_index(current_note_index);
                note_event <= 1'b1;
                duration_count <= 32'd0;
                tone_count <= 32'd0;
                spk <= 1'b0;
            end else begin
                duration_count <= duration_count + 32'd1;
            end
        end
    end
end

endmodule
