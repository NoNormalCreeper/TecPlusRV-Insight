// Minimal UART receiver with a one-byte holding register.
// Receives 8N1 frames, samples each bit near its center, and keeps data_valid
// asserted until the consumer pulses data_ready.
module uart_rx #(
    parameter integer CLK_FREQ = 50000000,
    parameter integer BAUD = 9600
) (
    input        clk,
    input        reset,
    input        rxd,
    input        data_ready,
    input        clear_overrun,
    input        clear_framing_error,
    output reg [7:0] data_out,
    output reg       data_valid,
    output reg       overrun,
    output reg       framing_error
);

localparam integer BAUD_DIV = (CLK_FREQ + (BAUD / 2)) / BAUD;
localparam integer HALF_BAUD_DIV = BAUD_DIV / 2;

localparam [1:0] STATE_IDLE  = 2'd0;
localparam [1:0] STATE_START = 2'd1;
localparam [1:0] STATE_DATA  = 2'd2;
localparam [1:0] STATE_STOP  = 2'd3;

reg rxd_meta;
reg rxd_sync;
reg [1:0] state;
reg [31:0] baud_count;
reg [2:0] bit_index;
reg [7:0] shift_reg;

// RXD is asynchronous to clk. The two flip-flops reduce metastability risk
// before the state machine observes the line.
always @(posedge clk) begin
    if (reset) begin
        rxd_meta <= 1'b1;
        rxd_sync <= 1'b1;
    end else begin
        rxd_meta <= rxd;
        rxd_sync <= rxd_meta;
    end
end

always @(posedge clk) begin
    if (reset) begin
        state <= STATE_IDLE;
        baud_count <= 32'd0;
        bit_index <= 3'd0;
        shift_reg <= 8'd0;
        data_out <= 8'd0;
        data_valid <= 1'b0;
        overrun <= 1'b0;
        framing_error <= 1'b0;
    end else begin
        if (data_ready) begin
            data_valid <= 1'b0;
        end

        if (clear_overrun) begin
            overrun <= 1'b0;
        end

        if (clear_framing_error) begin
            framing_error <= 1'b0;
        end

        case (state)
            STATE_IDLE: begin
                baud_count <= 32'd0;
                bit_index <= 3'd0;
                if (!rxd_sync) begin
                    state <= STATE_START;
                    baud_count <= HALF_BAUD_DIV - 1;
                end
            end

            STATE_START: begin
                if (baud_count == 0) begin
                    if (!rxd_sync) begin
                        state <= STATE_DATA;
                        baud_count <= BAUD_DIV - 1;
                    end else begin
                        // The line returned high before the start-bit center.
                        state <= STATE_IDLE;
                    end
                end else begin
                    baud_count <= baud_count - 1;
                end
            end

            STATE_DATA: begin
                if (baud_count == 0) begin
                    shift_reg[bit_index] <= rxd_sync;
                    baud_count <= BAUD_DIV - 1;
                    if (bit_index == 3'd7) begin
                        state <= STATE_STOP;
                    end else begin
                        bit_index <= bit_index + 1'b1;
                    end
                end else begin
                    baud_count <= baud_count - 1;
                end
            end

            default: begin
                if (baud_count == 0) begin
                    state <= STATE_IDLE;
                    if (rxd_sync) begin
                        if (data_valid && !data_ready) begin
                            // Keep the older unread byte and report the loss.
                            overrun <= 1'b1;
                        end else begin
                            data_out <= shift_reg;
                            data_valid <= 1'b1;
                        end
                    end else begin
                        framing_error <= 1'b1;
                    end
                end else begin
                    baud_count <= baud_count - 1;
                end
            end
        endcase
    end
end

endmodule
