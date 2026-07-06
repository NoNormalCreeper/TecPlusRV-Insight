module uart_tx #(
    parameter integer CLK_FREQ = 50000000,
    parameter integer BAUD = 9600
) (
    input        clk,
    input        reset,
    input        valid,
    input  [7:0] data_in,
    output       ready,
    output reg   txd
);

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
