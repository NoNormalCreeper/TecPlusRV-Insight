module bram_dualport #(
    parameter integer ADDR_WIDTH = 11,
    parameter integer USE_INIT_FILE = 0,
    parameter INIT_FILE = ""
) (
    input                  clk_a,
    input                  en_a,
    input  [ADDR_WIDTH-1:0] addr_a,
    input  [31:0]          wdata_a,
    input  [3:0]           wstrb_a,
    output reg [31:0]      rdata_a,
    input                  clk_b,
    input                  en_b,
    input  [ADDR_WIDTH-1:0] addr_b,
    output reg [31:0]      rdata_b
);

(* ram_style = "block" *)
reg [31:0] mem [0:(1 << ADDR_WIDTH) - 1];
// synthesis attribute ram_style of mem is block
integer i;

initial begin
    if (USE_INIT_FILE != 0) begin
        $readmemh(INIT_FILE, mem);
    end else begin
        for (i = 0; i < (1 << ADDR_WIDTH); i = i + 1) begin
            mem[i] = 32'h0000_0000;
        end
    end
end

always @(posedge clk_a) begin
    if (en_a) begin
        if (wstrb_a[0]) mem[addr_a][7:0] <= wdata_a[7:0];
        if (wstrb_a[1]) mem[addr_a][15:8] <= wdata_a[15:8];
        if (wstrb_a[2]) mem[addr_a][23:16] <= wdata_a[23:16];
        if (wstrb_a[3]) mem[addr_a][31:24] <= wdata_a[31:24];
        rdata_a <= mem[addr_a];
    end
end

always @(posedge clk_b) begin
    if (en_b) begin
        rdata_b <= mem[addr_b];
    end
end

endmodule
