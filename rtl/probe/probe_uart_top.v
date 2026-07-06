module probe_uart_top (
    input  clk,
    input  reset,
    input  uart_rxd,
    output uart_txd
);

localparam integer GAP_TICKS = 50000000;
localparam integer MSG_LEN = 17;

reg [25:0] gap_count;
reg [4:0]  msg_index;
reg        send_active;
reg        tx_valid;
reg [7:0]  tx_data;

wire rst;
wire tx_ready;

// 核心板 RESET 实测为低有效，top 内部统一转换为高有效 rst。
assign rst = !reset;

function [7:0] message_byte;
    input [4:0] index;
    begin
        case (index)
            5'd0:  message_byte = "H";
            5'd1:  message_byte = "e";
            5'd2:  message_byte = "l";
            5'd3:  message_byte = "l";
            5'd4:  message_byte = "o";
            5'd5:  message_byte = " ";
            5'd6:  message_byte = "T";
            5'd7:  message_byte = "e";
            5'd8:  message_byte = "c";
            5'd9:  message_byte = "P";
            5'd10: message_byte = "l";
            5'd11: message_byte = "u";
            5'd12: message_byte = "s";
            5'd13: message_byte = "R";
            5'd14: message_byte = "V";
            5'd15: message_byte = 8'h0d;
            default: message_byte = 8'h0a;
        endcase
    end
endfunction

uart_tx #(
    .CLK_FREQ(50000000),
    .BAUD(9600)
) u_uart_tx (
    .clk(clk),
    .reset(rst),
    .valid(tx_valid),
    .data_in(tx_data),
    .ready(tx_ready),
    .txd(uart_txd)
);

always @(posedge clk) begin
    if (rst) begin
        gap_count <= 26'd0;
        msg_index <= 5'd0;
        send_active <= 1'b0;
        tx_valid <= 1'b0;
        tx_data <= 8'd0;
    end else begin
        if (tx_valid && tx_ready) begin
            tx_valid <= 1'b0;

            if (msg_index == MSG_LEN - 1) begin
                send_active <= 1'b0;
                msg_index <= 5'd0;
            end else begin
                msg_index <= msg_index + 5'd1;
            end
        end else if (!send_active) begin
            // 留出消息间隔，方便实验室串口观察。
            if (gap_count == GAP_TICKS - 1) begin
                gap_count <= 26'd0;
                send_active <= 1'b1;
                msg_index <= 5'd0;
            end else begin
                gap_count <= gap_count + 26'd1;
            end
        end else if (!tx_valid) begin
            tx_data <= message_byte(msg_index);
            tx_valid <= 1'b1;
        end
    end
end

wire unused_uart_rxd;
assign unused_uart_rxd = uart_rxd;

endmodule
