// Probe 5a：大板 traffic-light 最小存在性探针。
// tl[11:0] 只做单 1 轮转，目标是确认排线/管脚/约束方向，
// 不是最终交通灯业务逻辑。
module probe_bigboard_tl_top #(
    parameter integer STEP_TICKS = 25_000_000
) (
    input         clk,
    input         reset,
    output reg [3:0]  led,
    output reg [11:0] tl
);

reg [24:0] tick_count;
wire rst;

// 核心板 RESET 实测为低有效，top 内部统一转换为高有效 rst。
assign rst = !reset;

always @(posedge clk) begin
    if (rst) begin
        tick_count <= 25'd0;
        tl <= 12'b0000_0000_0001;
        led <= 4'b0001;
    end else if (tick_count >= STEP_TICKS - 1) begin
        tick_count <= 25'd0;

        if (tl == 12'b1000_0000_0000) begin
            tl <= 12'b0000_0000_0001;
        end else begin
            tl <= {tl[10:0], 1'b0};
        end

        led <= {led[2:0], led[3]};
        if (led == 4'b0000) begin
            led <= 4'b0001;
        end
    end else begin
        tick_count <= tick_count + 25'd1;
    end
end

endmodule
