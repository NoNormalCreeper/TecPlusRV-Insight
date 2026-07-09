// CPU-controlled 12-bit traffic-light GPIO register.
// The output is intentionally raw: bit N drives TLN without polarity changes
// or built-in animation. Firmware decides the displayed pattern.
module traffic_light_gpio #(
    parameter [11:0] RESET_VALUE = 12'h000
) (
    input         clk,
    input         reset,
    input         write_en,
    input  [31:0] write_data,
    input  [3:0]  write_strobe,
    output reg [11:0] tl
);

always @(posedge clk) begin
    if (reset) begin
        tl <= RESET_VALUE;
    end else if (write_en) begin
        if (write_strobe[0]) begin
            tl[7:0] <= write_data[7:0];
        end
        if (write_strobe[1]) begin
            tl[11:8] <= write_data[11:8];
        end
    end
end

endmodule
