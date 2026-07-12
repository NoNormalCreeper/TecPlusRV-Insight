// 最小 UART 发送器，只负责 TX，不负责接收。
// 上层用 valid/ready 握手送入 1 个字节，本模块输出 8N1 帧：
// 1 个低电平起始位、8 个 LSB-first 数据位、1 个高电平停止位。
module uart_tx #(
    parameter integer CLK_FREQ = 50000000,
    parameter integer BAUD = 115200
) (
    input        clk,
    input        reset,
    input        valid,
    input  [7:0] data_in,
    output       ready,
    output reg   txd
);

// 四舍五入得到每个 bit 占多少个 clk。50 MHz / 115200 不是整数，
// 这里的误差对早期串口探针足够小，但不是高精度 baud generator。
localparam integer BAUD_DIV = (CLK_FREQ + (BAUD / 2)) / BAUD;

reg [15:0] baud_count;
reg [3:0]  bit_index;
reg [7:0]  shift_reg;
reg        busy;

assign ready = !busy;

always @(posedge clk) begin
    if (reset) begin
        baud_count <= 16'd0;
        bit_index <= 4'd0;
        shift_reg <= 8'd0;
        busy <= 1'b0;
        txd <= 1'b1;
    end else if (!busy) begin
        // 空闲线保持高电平；valid 只在 ready=1 时会被接收。
        txd <= 1'b1;
        baud_count <= 16'd0;
        bit_index <= 4'd0;

        if (valid) begin
            busy <= 1'b1;
            shift_reg <= data_in;
            // 起始位。
            txd <= 1'b0;
        end
    end else if (baud_count == BAUD_DIV - 1) begin
        baud_count <= 16'd0;

        // 按 LSB 优先发送数据位，最后发送停止位。
        case (bit_index)
            4'd0: begin
                txd <= shift_reg[0];
                bit_index <= 4'd1;
            end
            4'd1: begin
                txd <= shift_reg[1];
                bit_index <= 4'd2;
            end
            4'd2: begin
                txd <= shift_reg[2];
                bit_index <= 4'd3;
            end
            4'd3: begin
                txd <= shift_reg[3];
                bit_index <= 4'd4;
            end
            4'd4: begin
                txd <= shift_reg[4];
                bit_index <= 4'd5;
            end
            4'd5: begin
                txd <= shift_reg[5];
                bit_index <= 4'd6;
            end
            4'd6: begin
                txd <= shift_reg[6];
                bit_index <= 4'd7;
            end
            4'd7: begin
                txd <= shift_reg[7];
                bit_index <= 4'd8;
            end
            4'd8: begin
                txd <= 1'b1;
                bit_index <= 4'd9;
            end
            default: begin
                txd <= 1'b1;
                bit_index <= 4'd0;
                busy <= 1'b0;
            end
        endcase
    end else begin
        baud_count <= baud_count + 16'd1;
    end
end

endmodule
