module bram #(
    parameter integer ADDR_WIDTH = 11,
    parameter integer USE_INIT_FILE = 0,
    parameter INIT_FILE = ""
) (
    input              clk,
    input              en,
    input  [ADDR_WIDTH-1:0] addr,
    input  [31:0]      wdata,
    input  [3:0]       wstrb,
    output reg [31:0]  rdata
);

reg [31:0] mem [0:(1 << ADDR_WIDTH) - 1];
integer i;

initial begin
    if (USE_INIT_FILE != 0) begin
        // 主要服务于早期仿真和上板准备；综合后的行为仍要在 ISE 流程中复核。
        $readmemh(INIT_FILE, mem);
    end else begin
        for (i = 0; i < (1 << ADDR_WIDTH); i = i + 1) begin
            mem[i] = 32'h0000_0000;
        end
    end
end

always @(posedge clk) begin
    if (en) begin
        if (wstrb[0]) mem[addr][7:0] <= wdata[7:0];
        if (wstrb[1]) mem[addr][15:8] <= wdata[15:8];
        if (wstrb[2]) mem[addr][23:16] <= wdata[23:16];
        if (wstrb[3]) mem[addr][31:24] <= wdata[31:24];
        rdata <= mem[addr];
    end
end

endmodule
