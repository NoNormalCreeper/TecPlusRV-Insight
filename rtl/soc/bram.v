// 简单 32-bit BRAM 模型。
// 用于早期 MiniSoC 仿真和之后的片上小内存占位；接口保留字节写使能，
// 这样可以直接承接 PicoRV32 native memory interface 的 wstrb。
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

(* ram_style = "block" *)
reg [31:0] mem [0:(1 << ADDR_WIDTH) - 1];
// synthesis attribute ram_style of mem is block
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
        // wstrb 每一位控制一个 byte lane，支持 sb/sh/sw 这类不同宽度写入。
        if (wstrb[0]) mem[addr][7:0] <= wdata[7:0];
        if (wstrb[1]) mem[addr][15:8] <= wdata[15:8];
        if (wstrb[2]) mem[addr][23:16] <= wdata[23:16];
        if (wstrb[3]) mem[addr][31:24] <= wdata[31:24];
        // 同步读：rdata 在时钟沿后更新，testbench 要等一个 delta/周期再检查。
        rdata <= mem[addr];
    end
end

endmodule
