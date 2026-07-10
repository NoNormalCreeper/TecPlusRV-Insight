module darkriscv_adapter (
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
    input  [31:0] mem_rdata,
    // SoC shell 的稳定计数器契约。
    // 以后接入新 CPU 时，应优先补齐这对输出，而不是重新引入 top-level proxy counting。
    output [31:0] counter_cycle,
    output [31:0] counter_instret
);

wire        ibus_req;
wire [31:0] ibus_addr;
wire [31:0] ibus_rdata;
wire        ibus_ack;

wire        dbus_req;
wire [31:0] dbus_addr;
wire [2:0]  dbus_len;
wire [3:0]  dbus_be;
wire        dbus_rw;
wire        dbus_rd;
wire        dbus_wr;
wire [31:0] dbus_wdata;

wire [3:0]  debug;

assign ifetch_valid = ibus_req;
assign ifetch_addr = ibus_addr;
assign mem_valid = dbus_req;
assign mem_instr = 1'b0;
assign mem_addr = dbus_addr;
assign mem_wdata = dbus_wdata;
assign mem_wstrb = dbus_wr ? dbus_be : 4'b0000;

darkriscv u_cpu (
    .CLK(clk),
    .RES(!resetn),
    // Task 4 再由 SoC 接入真实 external/timer IRQ；当前保持现有行为。
    .IRQ(1'b0),
    .MTIP(1'b0),
    .IDREQ(ibus_req),
    .IADDR(ibus_addr),
    .IDATA(ifetch_rdata),
    .IDACK(ifetch_ready),
    .IBERR(1'b0),
    .DDREQ(dbus_req),
    .DADDR(dbus_addr),
    .DLEN(dbus_len),
    .DBE(dbus_be),
    .DRW(dbus_rw),
    .DRD(dbus_rd),
    .DWR(dbus_wr),
    .DATAO(dbus_wdata),
    .DATAI(mem_rdata),
    .DDACK(mem_ready),
    .DBERR(1'b0),
    .PERF_CYCLE(counter_cycle),
    .PERF_INSTRET(counter_instret),
    .DEBUG(debug)
);

endmodule
