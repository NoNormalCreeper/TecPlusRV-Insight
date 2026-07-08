// Probe 5a：大板 traffic-light 最小存在性探针。
// tl[11:0] 输出四段诊断图样：全 0、全 1、单 1 轮转、单 0 轮转。
// 目标是确认排线/管脚/约束方向和外设有效电平，不是最终交通灯业务逻辑。
module probe_bigboard_tl_top #(
    parameter integer STEP_TICKS = 25_000_000
) (
    input         clk,
    input         reset,
    output [3:0]  led,
    output [11:0] tl
);

localparam [1:0] PHASE_ALL_LOW  = 2'd0;
localparam [1:0] PHASE_ALL_HIGH = 2'd1;
localparam [1:0] PHASE_WALK_ONE = 2'd2;
localparam [1:0] PHASE_WALK_ZERO = 2'd3;

reg [31:0] tick_count;
reg [1:0]  phase;
reg [3:0]  scan_index;

wire rst;
wire step_done;
wire [11:0] scan_bit;

// 核心板 RESET 实测为低有效，top 内部统一转换为高有效 rst。
assign rst = !reset;
assign step_done = (tick_count >= STEP_TICKS - 1);
assign scan_bit = 12'h001 << scan_index;

assign tl = (phase == PHASE_ALL_LOW)  ? 12'h000 :
            (phase == PHASE_ALL_HIGH) ? 12'hfff :
            (phase == PHASE_WALK_ONE) ? scan_bit :
                                        ~scan_bit;

// 板载 LED 显示当前诊断阶段，方便和大板现象对照。
assign led = (phase == PHASE_ALL_LOW)  ? 4'b0001 :
             (phase == PHASE_ALL_HIGH) ? 4'b0010 :
             (phase == PHASE_WALK_ONE) ? 4'b0100 :
                                         4'b1000;

always @(posedge clk) begin
    if (rst) begin
        tick_count <= 32'd0;
        phase <= PHASE_ALL_LOW;
        scan_index <= 4'd0;
    end else if (step_done) begin
        tick_count <= 32'd0;

        if (phase == PHASE_ALL_LOW) begin
            phase <= PHASE_ALL_HIGH;
            scan_index <= 4'd0;
        end else if (phase == PHASE_ALL_HIGH) begin
            phase <= PHASE_WALK_ONE;
            scan_index <= 4'd0;
        end else if (scan_index == 4'd11) begin
            scan_index <= 4'd0;
            if (phase == PHASE_WALK_ONE) begin
                phase <= PHASE_WALK_ZERO;
            end else begin
                phase <= PHASE_ALL_LOW;
            end
        end else begin
            scan_index <= scan_index + 4'd1;
        end
    end else begin
        tick_count <= tick_count + 32'd1;
    end
end

endmodule
