// CLINT-like machine timer：64-bit 自增计数器、比较寄存器与 level IRQ。
// 对 mtime 的写入只覆盖选中的 32-bit 半字，并优先于该半字同拍自增。
module machine_timer (
    input clk,
    input reset,
    input mtime_lo_we,
    input mtime_hi_we,
    input mtimecmp_lo_we,
    input mtimecmp_hi_we,
    input [31:0] wdata,
    output [31:0] mtime_lo_rdata,
    output [31:0] mtime_hi_rdata,
    output [31:0] mtimecmp_lo_rdata,
    output [31:0] mtimecmp_hi_rdata,
    output irq
);

reg [63:0] mtime;
reg [63:0] mtimecmp;
wire [63:0] mtime_incremented = mtime + 64'd1;

assign mtime_lo_rdata = mtime[31:0];
assign mtime_hi_rdata = mtime[63:32];
assign mtimecmp_lo_rdata = mtimecmp[31:0];
assign mtimecmp_hi_rdata = mtimecmp[63:32];
assign irq = (mtime >= mtimecmp);

always @(posedge clk) begin
    if (reset) begin
        mtime <= 64'd0;
        mtimecmp <= 64'hffff_ffff_ffff_ffff;
    end else begin
        mtime[31:0] <= mtime_lo_we ? wdata : mtime_incremented[31:0];
        mtime[63:32] <= mtime_hi_we ? wdata : mtime_incremented[63:32];
        if (mtimecmp_lo_we) begin
            mtimecmp[31:0] <= wdata;
        end
        if (mtimecmp_hi_we) begin
            mtimecmp[63:32] <= wdata;
        end
    end
end

endmodule
