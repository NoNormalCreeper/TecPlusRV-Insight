// Probe 0：LED/KEY 最小板级探针。
// 目的不是实现复杂功能，而是确认 clk/reset/LED/KEY 的管脚和极性正确。
// reset 输入来自 TEC-PLUS 核心板，实测低有效；模块内部统一转成高有效 rst。
module probe_led_key_top (
    input        clk,
    input        reset,
    input  [3:0] key,
    output reg [3:0] led
);

localparam [25:0] SLOW_TICKS = 26'd24_999_999;
localparam [25:0] FAST_TICKS = 26'd4_999_999;

reg [25:0] tick_count;
reg [3:0]  key_prev;
reg        speed_fast;
reg        fixed_mode;

wire rst;
wire key1_pressed;
wire key2_pressed;
wire [25:0] tick_limit;

// 核心板 RESET 实测为低有效，top 内部统一转换为高有效 rst。
assign rst = !reset;
// KEY 默认为高，按下为低；用上一拍和当前拍做一个简单下降沿检测。
// 这里没有做消抖，故意保持 probe 很薄，真实按键抖动由实验现象判断。
assign key1_pressed = key_prev[0] && !key[0];
assign key2_pressed = key_prev[1] && !key[1];
assign tick_limit = speed_fast ? FAST_TICKS : SLOW_TICKS;

always @(posedge clk) begin
    if (rst) begin
        tick_count <= 26'd0;
        key_prev <= 4'b1111;
        speed_fast <= 1'b0;
        fixed_mode <= 1'b0;
        led <= 4'b0000;
    end else begin
        key_prev <= key;

        if (key1_pressed) begin
            speed_fast <= !speed_fast;
        end

        if (key2_pressed) begin
            fixed_mode <= !fixed_mode;
        end

        // 固定显示模式故意保持简单，便于实验室快速判断现象。
        if (fixed_mode) begin
            tick_count <= 26'd0;
            led <= 4'b1010;
        end else if (tick_count >= tick_limit) begin
            tick_count <= 26'd0;

            // 单灯跑马模式用于最早期板级冒烟测试。
            case (led)
                4'b0000: led <= 4'b0001;
                4'b0001: led <= 4'b0010;
                4'b0010: led <= 4'b0100;
                4'b0100: led <= 4'b1000;
                default: led <= 4'b0001;
            endcase
        end else begin
            tick_count <= tick_count + 26'd1;
        end
    end
end

endmodule
