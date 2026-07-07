module tecplus_cpu_wrapper #(
    parameter integer CPU_IMPL = 0,
    parameter [31:0] STACKADDR = 32'hffff_ffff
) (
    input         clk,
    input         resetn,
    output        ifetch_valid,
    output [31:0] ifetch_addr,
    input         ifetch_ready,
    input  [31:0] ifetch_rdata,
    output        mem_valid,
    output        mem_instr,
    input         mem_ready,
    output [31:0] mem_addr,
    output [31:0] mem_wdata,
    output [3:0]  mem_wstrb,
    input  [31:0] mem_rdata
);

localparam integer CPU_IMPL_PICORV32 = 0;
localparam integer CPU_IMPL_DARKRISCV = 1;

generate
    if (CPU_IMPL == CPU_IMPL_DARKRISCV) begin : g_darkriscv
        darkriscv_adapter u_cpu (
            .clk(clk),
            .resetn(resetn),
            .ifetch_valid(ifetch_valid),
            .ifetch_addr(ifetch_addr),
            .ifetch_ready(ifetch_ready),
            .ifetch_rdata(ifetch_rdata),
            .mem_valid(mem_valid),
            .mem_instr(mem_instr),
            .mem_ready(mem_ready),
            .mem_addr(mem_addr),
            .mem_wdata(mem_wdata),
            .mem_wstrb(mem_wstrb),
            .mem_rdata(mem_rdata)
        );
    end else begin : g_picorv32
        picorv32_adapter #(
            .STACKADDR(STACKADDR)
        ) u_cpu (
            .clk(clk),
            .resetn(resetn),
            .ifetch_valid(ifetch_valid),
            .ifetch_addr(ifetch_addr),
            .ifetch_ready(ifetch_ready),
            .ifetch_rdata(ifetch_rdata),
            .mem_valid(mem_valid),
            .mem_instr(mem_instr),
            .mem_ready(mem_ready),
            .mem_addr(mem_addr),
            .mem_wdata(mem_wdata),
            .mem_wstrb(mem_wstrb),
            .mem_rdata(mem_rdata)
        );
    end
endgenerate

endmodule
