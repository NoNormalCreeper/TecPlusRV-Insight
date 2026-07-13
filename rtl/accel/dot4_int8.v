// 四路 signed INT8 点积协处理器。
// req 首次拉高时锁存结果，下一拍给出单周期 ack；req 撤销前不重复接收。
module dot4_int8 (
    input             clk,
    input             reset,
    input             req,
    input      [31:0] rs1,
    input      [31:0] rs2,
    output reg        ack,
    output reg [31:0] result
);

localparam [1:0] STATE_IDLE = 2'd0;
localparam [1:0] STATE_RESPOND = 2'd1;
localparam [1:0] STATE_WAIT_DROP = 2'd2;

reg [1:0] state;

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

always @(posedge clk) begin
    if (reset) begin
        state <= STATE_IDLE;
        ack <= 1'b0;
        result <= 32'h0000_0000;
    end else begin
        ack <= 1'b0;
        case (state)
            STATE_IDLE: begin
                if (req) begin
                    result <= {{14{sum[17]}}, sum};
                    state <= STATE_RESPOND;
                end
            end
            STATE_RESPOND: begin
                ack <= 1'b1;
                state <= STATE_WAIT_DROP;
            end
            STATE_WAIT_DROP: begin
                if (!req)
                    state <= STATE_IDLE;
            end
            default: begin
                state <= STATE_IDLE;
            end
        endcase
    end
end

endmodule
