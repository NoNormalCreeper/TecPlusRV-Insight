// Probe 5c：蜂鸣器 + UART 调试版。
// 目标不是做音频子系统，而是先回答三件事：
// 1. `Spk` 这条最小输出链路是不是活的
// 2. 蜂鸣器大致能否播放指定旋律
// 3. 串口能否同步给出每个音符切换 token，辅助板级调试
module probe_buzzer_uart_top #(
    parameter integer CLK_FREQ = 50000000,
    parameter integer UART_BAUD = 9600,
    parameter integer BEAT_TICKS = 25000000,
    parameter MF_DEFAULT = 1'b0,
    parameter CLR_DEFAULT = 1'b1,
    parameter [7:0] S_DEFAULT = 8'h00
) (
    input clk,
    input reset,
    input uart_rxd,
    output uart_txd,
    output [3:0] led,
    output mf,
    output clr,
    output spk,
    output [7:0] s
);

wire rst;
wire [2:0] current_note_index;
wire [2:0] event_note_index;
wire note_event;
wire reporter_valid;
wire [7:0] reporter_data;
wire uart_ready;
wire reporter_busy;

assign rst = !reset;
assign led = {spk, current_note_index};
assign mf = MF_DEFAULT;
assign clr = CLR_DEFAULT;
assign s = S_DEFAULT;

buzzer_tune_player #(
    .CLK_FREQ(CLK_FREQ),
    .BEAT_TICKS(BEAT_TICKS)
) player (
    .clk(clk),
    .reset(rst),
    .spk(spk),
    .current_note_index(current_note_index),
    .event_note_index(event_note_index),
    .note_event(note_event)
);

buzzer_uart_reporter reporter (
    .clk(clk),
    .reset(rst),
    .note_event(note_event),
    .event_note_index(event_note_index),
    .tx_ready(uart_ready),
    .tx_valid(reporter_valid),
    .tx_data(reporter_data),
    .busy(reporter_busy)
);

uart_tx #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD(UART_BAUD)
) u_uart_tx (
    .clk(clk),
    .reset(rst),
    .valid(reporter_valid),
    .data_in(reporter_data),
    .ready(uart_ready),
    .txd(uart_txd)
);

wire unused_uart_rxd;
wire unused_reporter_busy;
assign unused_uart_rxd = uart_rxd;
assign unused_reporter_busy = reporter_busy;

endmodule
