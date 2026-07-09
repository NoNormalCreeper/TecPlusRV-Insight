// Programmable square-wave generator for the board buzzer.
// HALF_PERIOD is measured in clk cycles. A value of zero keeps SPK low.
module buzzer_pwm (
    input         clk,
    input         reset,
    input         ctrl_write_en,
    input         period_write_en,
    input  [31:0] write_data,
    input  [3:0]  write_strobe,
    output reg    enabled,
    output reg [31:0] half_period,
    output reg    spk
);

reg [31:0] count;

always @(posedge clk) begin
    if (reset) begin
        enabled <= 1'b0;
        half_period <= 32'd0;
        count <= 32'd0;
        spk <= 1'b0;
    end else if (ctrl_write_en && write_strobe[0]) begin
        enabled <= write_data[0];
        count <= 32'd0;
        spk <= 1'b0;
    end else if (period_write_en) begin
        if (write_strobe[0]) begin
            half_period[7:0] <= write_data[7:0];
        end
        if (write_strobe[1]) begin
            half_period[15:8] <= write_data[15:8];
        end
        if (write_strobe[2]) begin
            half_period[23:16] <= write_data[23:16];
        end
        if (write_strobe[3]) begin
            half_period[31:24] <= write_data[31:24];
        end
        count <= 32'd0;
        spk <= 1'b0;
    end else if (!enabled || (half_period == 0)) begin
        count <= 32'd0;
        spk <= 1'b0;
    end else if (count >= half_period - 1) begin
        count <= 32'd0;
        spk <= !spk;
    end else begin
        count <= count + 1'b1;
    end
end

endmodule
