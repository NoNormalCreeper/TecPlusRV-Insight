module darkriscv_adapter (
    input         clk,
    input         resetn,
    input         irq_external,
    input         irq_timer,
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
wire        cpr_req;
wire [2:0]  cpr_fct3;
wire [6:0]  cpr_fct7;
wire [31:0] cpr_pc;
wire [31:0] cpr_rs1;
wire [31:0] cpr_rs2;
wire [31:0] cpr_rdr;
wire [31:0] cpr_rdw;
wire        cpr_ack;

assign ifetch_valid = ibus_req;
assign ifetch_addr = ibus_addr;
assign mem_valid = dbus_req;
assign mem_instr = 1'b0;
assign mem_addr = dbus_addr;
assign mem_wdata = dbus_wdata;
assign mem_wstrb = dbus_wr ? dbus_be : 4'b0000;

dot4_int8 u_dot4 (
    .clk(clk),
    .reset(!resetn),
    .req(cpr_req),
    .tag(cpr_pc),
    .rs1(cpr_rs1),
    .rs2(cpr_rs2),
    .ack(cpr_ack),
    .result(cpr_rdw)
);

darkriscv u_cpu (
    .CLK(clk),
    .RES(!resetn),
    .IRQ(irq_external),
    .MTIP(irq_timer),
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
    .CPR_REQ(cpr_req),
    .CPR_FCT3(cpr_fct3),
    .CPR_FCT7(cpr_fct7),
    .CPR_PC(cpr_pc),
    .CPR_RS1(cpr_rs1),
    .CPR_RS2(cpr_rs2),
    .CPR_RDR(cpr_rdr),
    .CPR_RDW(cpr_rdw),
    .CPR_ACK(cpr_ack),
    .PERF_CYCLE(counter_cycle),
    .PERF_INSTRET(counter_instret),
    .DEBUG(debug)
);

endmodule
