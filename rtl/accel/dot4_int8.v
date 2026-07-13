// 四路 signed INT8 点积协处理器。
// req 有效时锁存结果；tag 绑定当前指令，防止流水线停顿时重复接收同一请求。
module dot4_int8 (
    input             clk,
    input             reset,
    input             req,
    input      [31:0] tag,
    input      [31:0] rs1,
    input      [31:0] rs2,
    output            ack,
    output reg [31:0] result
);

reg result_valid;
reg [31:0] result_tag;

wire signed [7:0] a0 = rs1[7:0];
wire signed [7:0] a1 = rs1[15:8];
wire signed [7:0] a2 = rs1[23:16];
wire signed [7:0] a3 = rs1[31:24];
wire signed [7:0] b0 = rs2[7:0];
wire signed [7:0] b1 = rs2[15:8];
wire signed [7:0] b2 = rs2[23:16];
wire signed [7:0] b3 = rs2[31:24];

wire signed [15:0] product0 = a0 * b0;
wire signed [15:0] product1 = a1 * b1;
wire signed [15:0] product2 = a2 * b2;
wire signed [15:0] product3 = a3 * b3;
wire signed [17:0] sum =
    {{2{product0[15]}}, product0} +
    {{2{product1[15]}}, product1} +
    {{2{product2[15]}}, product2} +
    {{2{product3[15]}}, product3};

// 结果只对产生它的 instruction PC 有效。相邻 custom 指令即使 req 连续为高，
// tag 改变也会立即撤销旧 ack，让 CPU 为新结果停顿。
assign ack = result_valid && req && (tag == result_tag);

always @(posedge clk) begin
    if (reset) begin
        result_valid <= 1'b0;
        result_tag <= 32'h0000_0000;
        result <= 32'h0000_0000;
    end else begin
        if (!req) begin
            result_valid <= 1'b0;
        end else if (!result_valid || tag != result_tag) begin
            result <= {{14{sum[17]}}, sum};
            result_tag <= tag;
            result_valid <= 1'b1;
        end
    end
end

endmodule
