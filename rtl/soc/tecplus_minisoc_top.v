// TEC-PLUS MiniSoC 板级顶层。
// CPU 总线留在 FPGA 内部，数据访问分流到 BRAM、TinyBus MMIO 与 SDRAM。
`include "tinybus_defs.vh"

module tecplus_minisoc_top #(
    parameter integer CLK_FREQ = 50000000,
    parameter integer UART_BAUD = 9600,
    parameter integer CPU_IMPL = 0,
    parameter integer BRAM_ADDR_WIDTH = 14,
    parameter integer SDRAM_CLK_INVERT = 1,
    parameter integer BOOTLOADER_ENABLE = 0,
    parameter integer BOOT_TIMEOUT_CYCLES = CLK_FREQ,
    // 当前 writable text/tile 原型在 LX9 MiniSoC 中会 overmap，默认不参与综合。
    // 只在保留的 Bad Apple 仿真或后续资源实验中显式设为 1。
    parameter integer VGA_TEXT_ENABLE = 0,
    parameter VGA_MF_DEFAULT = 1'b0,
    parameter VGA_CLR_DEFAULT = 1'b1,
    parameter VGA_QD_DEFAULT = 1'b0,
    parameter BRAM_INIT_FILE = "firmware/build/firmware.mem"
) (
    input        clk,
    input        reset,
    input  [3:0] key,
    output reg [3:0] led,
    input        uart_rxd,
    output       uart_txd,
    output [11:0] tl,
    output       spk,
    output       vga_r,
    output       vga_g,
    output       vga_b,
    output       vga_hs,
    output       vga_vs,
    output       vga_mf,
    output       vga_clr,
    output       vga_qd,
    output       sh_clk,
    output       sh_cke,
    output       sh_ncs,
    output       sh_nwe,
    output       sh_ncas,
    output       sh_nras,
    output [1:0] sh_dqm,
    output [1:0] sh_ba,
    output [12:0] sh_a,
    inout  [15:0] sh_db
);

localparam [31:0] BRAM_BYTES = (32'd1 << BRAM_ADDR_WIDTH) * 32'd4;
localparam [31:0] SDRAM_SIZE = 32'h0200_0000; // U2 x16 256 Mbit = 32 MiB

wire resetn;
wire rst;

wire        ifetch_valid;
wire [31:0] ifetch_addr;
wire        ifetch_ready;
wire [31:0] ifetch_rdata;

wire        mem_valid;
wire        mem_instr;
reg         mem_ready;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire [3:0]  mem_wstrb;
reg  [31:0] mem_rdata;

wire        start_req;
wire        bram_en;
wire [BRAM_ADDR_WIDTH-1:0] bram_addr;
wire [31:0] bram_wdata;
wire [3:0] bram_wstrb;
wire [31:0] bram_data_rdata;
wire        cpu_bram_en;
wire [BRAM_ADDR_WIDTH-1:0] cpu_bram_addr;

wire        ifetch_is_bram;
wire        ifetch_en;
wire [BRAM_ADDR_WIDTH-1:0] ifetch_bram_addr;
wire [31:0] ifetch_bram_rdata;

reg         pending;
reg         ifetch_pending;
reg         req_is_bram;
reg         req_is_sdram;
reg         req_is_mmio;
reg         req_we_reg;
reg         req_is_replay;
reg         sdram_req_sent;
reg  [31:0] req_addr;
reg  [31:0] req_wdata;
reg  [3:0]  req_wstrb;
reg         last_req_valid;
reg  [31:0] last_req_addr;
reg  [31:0] last_req_wdata;
reg  [3:0]  last_req_wstrb;
reg  [31:0] last_req_rdata;

wire [31:0] gpio_key_rdata;
wire [31:0] uart_data_rdata;
wire [31:0] uart_status_rdata;
wire [31:0] cycle_rdata;
wire [31:0] instret_rdata;
wire [31:0] traffic_rdata;
wire [31:0] buzzer_ctrl_rdata;
wire [31:0] buzzer_period_rdata;
wire [31:0] vga_status_rdata;
wire [31:0] cpu_cycle_count;
wire [31:0] cpu_instret_count;
wire [31:0] mmio_rdata;
wire        mmio_write_en;
wire        gpio_led_sel;
wire        uart_data_sel;
wire        uart_status_sel;
wire        test_exit_sel;
wire        traffic_sel;
wire        buzzer_ctrl_sel;
wire        buzzer_period_sel;
wire        vga_status_sel;
wire        vga_tile_sel;
wire        uart_tx_ready;
wire        uart_fire;
wire [7:0]  uart_rx_data;
wire        uart_rx_valid;
wire        uart_rx_overrun;
wire        uart_rx_framing_error;
wire        uart_rx_consume;
wire        uart_overrun_clear;
wire        uart_framing_error_clear;
wire        uart_rx_ready;
wire        uart_rx_overrun_clear;
wire        uart_rx_framing_error_clear;
wire        uart_tx_valid;
wire [7:0]  uart_tx_data;
wire        boot_active;
wire        boot_cpu_release;
wire        boot_rx_ready;
wire        boot_rx_overrun_clear;
wire        boot_rx_framing_error_clear;
wire        boot_tx_valid;
wire [7:0]  boot_tx_data;
wire        boot_bram_en;
wire [BRAM_ADDR_WIDTH-1:0] boot_bram_addr;
wire [31:0] boot_bram_wdata;
wire [3:0]  boot_bram_wstrb;
wire        boot_sdram_req_valid;
wire [31:0] boot_sdram_req_addr;
wire [31:0] boot_sdram_req_wdata;
wire [3:0]  boot_sdram_req_wstrb;
wire [7:0]  boot_last_error;
wire        test_exit_write;
wire        traffic_write;
wire        buzzer_ctrl_write;
wire        buzzer_period_write;
wire        vga_tile_write;
wire        vga_ready;
wire        vga_vblank;
wire [15:0] vga_frame_count;
wire [8:0]  vga_tile_addr;
wire        buzzer_enabled;
wire [31:0] buzzer_half_period;
wire        mmio_stall;
// SDRAM 内部请求与物理数据通路。
wire        sdram_req_valid;
wire        cpu_sdram_req_valid;
wire        sdram_req_fire;
wire        sdram_req_ready;
wire        sdram_resp_valid;
wire [31:0] sdram_resp_rdata;
wire        sdram_resp_err;
wire [15:0] sdram_dq_in;
wire [15:0] sdram_dq_out;
wire        sdram_dq_oe;

wire        test_exited;
wire [31:0] test_exit_code;
wire        same_as_last_req;
wire [31:0] response_rdata;

wire bram_done   = req_is_bram;
wire mmio_done   = req_is_mmio && !mmio_stall;
wire sdram_done  = req_is_sdram && (req_is_replay || sdram_resp_valid);
wire respond     = pending && (bram_done || mmio_done || sdram_done);

assign resetn = reset && boot_cpu_release;
assign rst = !reset;
assign sh_clk = (SDRAM_CLK_INVERT != 0) ? !clk : clk;
assign sh_db = sdram_dq_oe ? sdram_dq_out : 16'hzzzz;
assign sdram_dq_in = sh_db;
assign vga_mf = VGA_MF_DEFAULT;
assign vga_clr = VGA_CLR_DEFAULT;
assign vga_qd = VGA_QD_DEFAULT;

assign start_req = mem_valid && !pending && !mem_ready;
wire is_bram   = (mem_addr < BRAM_BYTES);
wire is_sdram  = (mem_addr >= `TINYBUS_ADDR_SDRAM_BASE && mem_addr < `TINYBUS_ADDR_SDRAM_BASE + SDRAM_SIZE);
wire is_mmio   = !(is_bram || is_sdram);   // 包括 0x1000_0000 和 0x2000_0000 等
assign cpu_bram_en = start_req && is_bram;
assign cpu_bram_addr = mem_addr[BRAM_ADDR_WIDTH+1:2];
assign boot_active = (BOOTLOADER_ENABLE != 0) && !boot_cpu_release;
assign bram_en = boot_active ? boot_bram_en : cpu_bram_en;
assign bram_addr = boot_active ? boot_bram_addr : cpu_bram_addr;
assign bram_wdata = boot_active ? boot_bram_wdata : mem_wdata;
assign bram_wstrb = boot_active ? boot_bram_wstrb : mem_wstrb;
assign ifetch_is_bram = (ifetch_addr < BRAM_BYTES);
assign ifetch_en = ifetch_valid && !ifetch_pending && ifetch_is_bram;
assign ifetch_bram_addr = ifetch_addr[BRAM_ADDR_WIDTH+1:2];
assign ifetch_ready = ifetch_pending;
assign ifetch_rdata = ifetch_bram_rdata;

assign gpio_key_rdata = {28'h0000000, key};
assign uart_data_rdata = {24'h000000, uart_rx_data};
assign uart_status_rdata = {
    28'h0000000,
    uart_rx_framing_error,
    uart_rx_overrun,
    uart_rx_valid,
    uart_tx_ready
};
// MMIO 可见的 counter 故意通过 wrapper 契约直接来自被选中的 CPU。
// 这里不要重新引入 local proxy counting，否则 instret 语义会再次偏离 core 自己的报告值。
assign cycle_rdata = cpu_cycle_count;
assign instret_rdata = cpu_instret_count;
assign traffic_rdata = {20'h00000, tl};
assign buzzer_ctrl_rdata = {31'h00000000, buzzer_enabled};
assign buzzer_period_rdata = buzzer_half_period;
assign vga_status_rdata = {vga_frame_count, 14'h0000, vga_ready, vga_vblank};
assign vga_tile_addr = (req_addr - `TINYBUS_ADDR_VGA_TILE_BASE) >> 2;

assign same_as_last_req =
    last_req_valid &&
    (mem_addr == last_req_addr) &&
    (mem_wstrb == last_req_wstrb) &&
    // DarkRISCV 在 read 期间不保证 dbus_wdata 的值；读重放只比较地址和
    // byte-enable，写重放才需要比较写数据。否则仿真中的 X 会传入
    // req_is_replay，并阻断 SDRAM ready-first 请求。
    ((mem_wstrb == 4'b0000) || (mem_wdata == last_req_wdata));

// sdram_data_ctrl 使用 ready-first 握手：仅在 ready 已拉高时提交一次请求。
// CPU 侧仍等待 resp_valid，sdram_req_sent 负责隔离“已提交”和“等待响应”。
assign cpu_sdram_req_valid =
    pending && req_is_sdram && !req_is_replay && !sdram_req_sent && sdram_req_ready;
// bootloader 运行时 CPU 保持 reset，因此这里只需切换 SDRAM 所有权，不需要通用 arbiter。
assign sdram_req_valid = boot_active ? boot_sdram_req_valid : cpu_sdram_req_valid;
assign sdram_req_fire = !boot_active && cpu_sdram_req_valid && sdram_req_ready;
assign response_rdata =
    (req_is_replay && req_is_sdram) ? last_req_rdata :
    req_is_bram   ? bram_data_rdata :
    req_is_sdram  ? sdram_resp_rdata : mmio_rdata;

assign mmio_stall = pending && req_is_mmio && !req_is_replay && uart_data_sel && mmio_write_en && !uart_tx_ready;
//assign respond = pending && !mmio_stall;
assign uart_fire = respond && req_is_mmio && !req_is_replay && uart_data_sel && mmio_write_en;
assign uart_rx_consume = respond && req_is_mmio && !req_is_replay && uart_data_sel && !mmio_write_en;
assign uart_overrun_clear =
    respond && req_is_mmio && !req_is_replay &&
    uart_status_sel && mmio_write_en && req_wdata[2];
assign uart_framing_error_clear =
    respond && req_is_mmio && !req_is_replay &&
    uart_status_sel && mmio_write_en && req_wdata[3];
assign uart_rx_ready = boot_active ? boot_rx_ready : uart_rx_consume;
assign uart_rx_overrun_clear = boot_active ? boot_rx_overrun_clear : uart_overrun_clear;
assign uart_rx_framing_error_clear =
    boot_active ? boot_rx_framing_error_clear : uart_framing_error_clear;
assign uart_tx_valid = boot_active ? boot_tx_valid : uart_fire;
assign uart_tx_data = boot_active ? boot_tx_data : req_wdata[7:0];
assign test_exit_write = respond && req_is_mmio && !req_is_replay && test_exit_sel && mmio_write_en;
assign traffic_write = respond && req_is_mmio && !req_is_replay && traffic_sel && mmio_write_en;
assign buzzer_ctrl_write = respond && !req_is_bram && !req_is_replay && buzzer_ctrl_sel && mmio_write_en;
assign buzzer_period_write = respond && !req_is_bram && !req_is_replay && buzzer_period_sel && mmio_write_en;
assign vga_tile_write =
    (VGA_TEXT_ENABLE != 0) && respond && req_is_mmio && !req_is_replay &&
    vga_tile_sel && mmio_write_en;

tecplus_cpu_wrapper #(
    .CPU_IMPL(CPU_IMPL),
    .STACKADDR(BRAM_BYTES)
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
    .mem_rdata(mem_rdata),
    .counter_cycle(cpu_cycle_count),
    .counter_instret(cpu_instret_count)
);

bram_dualport #(
    .ADDR_WIDTH(BRAM_ADDR_WIDTH),
    .USE_INIT_FILE(1),
    .INIT_FILE(BRAM_INIT_FILE)
) u_bram (
    .clk_a(clk),
    .en_a(bram_en),
    .addr_a(bram_addr),
    .wdata_a(bram_wdata),
    .wstrb_a(bram_wstrb),
    .rdata_a(bram_data_rdata),
    .clk_b(clk),
    .en_b(ifetch_en),
    .addr_b(ifetch_bram_addr),
    .rdata_b(ifetch_bram_rdata)
);

sdram_data_ctrl #(
    .PWRUP_WAIT_CYCLES(10000),
    .TRP_CYCLES(3),
    .TRFC_CYCLES(7),
    .TMRD_CYCLES(2),
    .TRCD_CYCLES(3),
    .TWR_CYCLES(3),
    .CAS_LATENCY_CYCLES(2),
    .REFI_CYCLES(300),
    .REFRESH_DEFER_CYCLES(32),
    .MODE_REG_VALUE(13'h220)
) u_sdram (
    .clk(clk),
    .reset(rst),
    .req_valid(sdram_req_valid),
    .req_ready(sdram_req_ready),
    .req_we(boot_active ? 1'b1 : req_we_reg),
    .req_addr(boot_active ? boot_sdram_req_addr : req_addr),
    .req_wdata(boot_active ? boot_sdram_req_wdata : req_wdata),
    .req_wstrb(boot_active ? boot_sdram_req_wstrb : req_wstrb),
    .resp_valid(sdram_resp_valid),
    .resp_rdata(sdram_resp_rdata),
    .resp_err(sdram_resp_err),
    .dq_in(sdram_dq_in),
    .dq_oe(sdram_dq_oe),
    .dq_out(sdram_dq_out),
    .sdram_cke(sh_cke),
    .sdram_cs_n(sh_ncs),
    .sdram_ras_n(sh_nras),
    .sdram_cas_n(sh_ncas),
    .sdram_we_n(sh_nwe),
    .sdram_ba(sh_ba),
    .sdram_addr(sh_a),
    .sdram_dqm(sh_dqm),
    .dbg_state(),
    .dbg_refresh_pending()
);

tinybus_decode u_decode (
    .valid(pending && req_is_mmio),
    .addr(req_addr),
    .wdata(req_wdata),
    .wstrb(req_wstrb),
    .gpio_key_rdata(gpio_key_rdata),
    .uart_data_rdata(uart_data_rdata),
    .uart_status_rdata(uart_status_rdata),
    .cycle_rdata(cycle_rdata),
    .instret_rdata(instret_rdata),
    .traffic_rdata(traffic_rdata),
    .buzzer_ctrl_rdata(buzzer_ctrl_rdata),
    .buzzer_period_rdata(buzzer_period_rdata),
    .vga_status_rdata(vga_status_rdata),
    .accel_rdata(32'h0000_0000),
    .rdata(mmio_rdata),
    .ready(),
    .write_en(mmio_write_en),
    .gpio_led_sel(gpio_led_sel),
    .gpio_key_sel(),
    .uart_data_sel(uart_data_sel),
    .uart_status_sel(uart_status_sel),
    .cycle_sel(),
    .instret_sel(),
    .test_exit_sel(test_exit_sel),
    .traffic_sel(traffic_sel),
    .buzzer_ctrl_sel(buzzer_ctrl_sel),
    .buzzer_period_sel(buzzer_period_sel),
    .vga_status_sel(vga_status_sel),
    .vga_tile_sel(vga_tile_sel),
    .accel_sel(),
    .write_data()
);

uart_tx #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD(UART_BAUD)
) u_uart_tx (
    .clk(clk),
    .reset(rst),
    .valid(uart_tx_valid),
    .data_in(uart_tx_data),
    .ready(uart_tx_ready),
    .txd(uart_txd)
);

uart_rx #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD(UART_BAUD)
) u_uart_rx (
    .clk(clk),
    .reset(rst),
    .rxd(uart_rxd),
    .data_ready(uart_rx_ready),
    .clear_overrun(uart_rx_overrun_clear),
    .clear_framing_error(uart_rx_framing_error_clear),
    .data_out(uart_rx_data),
    .data_valid(uart_rx_valid),
    .overrun(uart_rx_overrun),
    .framing_error(uart_rx_framing_error)
);

generate
    if (BOOTLOADER_ENABLE != 0) begin : g_bootloader
        bootloader_ctrl #(
            .BRAM_ADDR_WIDTH(BRAM_ADDR_WIDTH),
            .INTERBYTE_TIMEOUT_CYCLES(BOOT_TIMEOUT_CYCLES)
        ) u_bootloader (
            .clk(clk),
            .reset(rst),
            .rx_data(uart_rx_data),
            .rx_valid(uart_rx_valid),
            .rx_overrun(uart_rx_overrun),
            .rx_framing_error(uart_rx_framing_error),
            .rx_ready(boot_rx_ready),
            .clear_rx_overrun(boot_rx_overrun_clear),
            .clear_rx_framing_error(boot_rx_framing_error_clear),
            .tx_ready(uart_tx_ready),
            .tx_valid(boot_tx_valid),
            .tx_data(boot_tx_data),
            .bram_en(boot_bram_en),
            .bram_addr(boot_bram_addr),
            .bram_wdata(boot_bram_wdata),
            .bram_wstrb(boot_bram_wstrb),
            .sdram_req_valid(boot_sdram_req_valid),
            .sdram_req_ready(sdram_req_ready),
            .sdram_req_addr(boot_sdram_req_addr),
            .sdram_req_wdata(boot_sdram_req_wdata),
            .sdram_req_wstrb(boot_sdram_req_wstrb),
            .sdram_resp_valid(sdram_resp_valid),
            .sdram_resp_error(sdram_resp_err),
            .cpu_release(boot_cpu_release),
            .last_error(boot_last_error)
        );
    end else begin : g_no_bootloader
        assign boot_cpu_release = 1'b1;
        assign boot_rx_ready = 1'b0;
        assign boot_rx_overrun_clear = 1'b0;
        assign boot_rx_framing_error_clear = 1'b0;
        assign boot_tx_valid = 1'b0;
        assign boot_tx_data = 8'h00;
        assign boot_bram_en = 1'b0;
        assign boot_bram_addr = {BRAM_ADDR_WIDTH{1'b0}};
        assign boot_bram_wdata = 32'h0000_0000;
        assign boot_bram_wstrb = 4'b0000;
        assign boot_sdram_req_valid = 1'b0;
        assign boot_sdram_req_addr = 32'h0000_0000;
        assign boot_sdram_req_wdata = 32'h0000_0000;
        assign boot_sdram_req_wstrb = 4'b0000;
        assign boot_last_error = 8'h00;
    end
endgenerate

traffic_light_gpio u_traffic_light (
    .clk(clk),
    .reset(rst),
    .write_en(traffic_write),
    .write_data(req_wdata),
    .write_strobe(req_wstrb),
    .tl(tl)
);

buzzer_pwm u_buzzer (
    .clk(clk),
    .reset(rst),
    .ctrl_write_en(buzzer_ctrl_write),
    .period_write_en(buzzer_period_write),
    .write_data(req_wdata),
    .write_strobe(req_wstrb),
    .enabled(buzzer_enabled),
    .half_period(buzzer_half_period),
    .spk(spk)
);

generate
    if (VGA_TEXT_ENABLE != 0) begin : g_vga_text
        vga_text_mode u_vga_text (
            .clk(clk),
            .reset(rst),
            .tile_we(vga_tile_write),
            .tile_addr(vga_tile_addr),
            .tile_wdata(req_wdata),
            .tile_wstrb(req_wstrb),
            .ready(vga_ready),
            .vblank(vga_vblank),
            .frame_count(vga_frame_count),
            .vga_r(vga_r),
            .vga_g(vga_g),
            .vga_b(vga_b),
            .vga_hs(vga_hs),
            .vga_vs(vga_vs)
        );
    end else begin : g_no_vga_text
        assign vga_ready = 1'b0;
        assign vga_vblank = 1'b0;
        assign vga_frame_count = 16'h0000;
        assign vga_r = 1'b0;
        assign vga_g = 1'b0;
        assign vga_b = 1'b0;
        assign vga_hs = 1'b1;
        assign vga_vs = 1'b1;
    end
endgenerate

mmio_test_exit u_test_exit (
    .clk(clk),
    .reset(rst),
    .write_en(test_exit_write),
    .write_data(req_wdata),
    .exited(test_exited),
    .exit_code(test_exit_code)
);

always @(posedge clk) begin
    if (rst) begin
        pending <= 1'b0;
        ifetch_pending <= 1'b0;
        req_is_bram <= 1'b0;
        req_is_sdram <= 1'b0;
        req_is_mmio  <= 1'b0;
        req_we_reg   <= 1'b0;
        req_is_replay <= 1'b0;
        sdram_req_sent <= 1'b0;
        req_addr <= 32'h0000_0000;
        req_wdata <= 32'h0000_0000;
        req_wstrb <= 4'b0000;
        last_req_valid <= 1'b0;
        last_req_addr <= 32'h0000_0000;
        last_req_wdata <= 32'h0000_0000;
        last_req_wstrb <= 4'b0000;
        last_req_rdata <= 32'h0000_0000;
        mem_ready <= 1'b0;
        mem_rdata <= 32'h0000_0000;
        led <= 4'h0;
    end else begin
        mem_ready <= 1'b0;

        if (!mem_valid) begin
            last_req_valid <= 1'b0;
        end

        if (ifetch_pending) begin
            ifetch_pending <= 1'b0;
        end else if (ifetch_en) begin
            ifetch_pending <= 1'b1;
        end

        if (respond) begin
            pending <= 1'b0;
            mem_ready <= 1'b1;
            mem_rdata <= response_rdata;
            sdram_req_sent <= 1'b0;
            last_req_valid <= 1'b1;
            last_req_addr <= req_addr;
            last_req_wdata <= req_wdata;
            last_req_wstrb <= req_wstrb;
            if (!req_is_replay) begin
                last_req_rdata <= response_rdata;
            end

            if (!req_is_bram && !req_is_replay && gpio_led_sel && mmio_write_en) begin
                led <= req_wdata[3:0];
            end
        end else if (start_req) begin
            pending <= 1'b1;
            req_is_bram  <= is_bram;
            req_is_sdram <= is_sdram;
            req_is_mmio  <= is_mmio;
            req_we_reg   <= (mem_wstrb != 4'b0);   // 只要有任一字节有效，即视为写操作
            req_is_replay <= same_as_last_req;
            sdram_req_sent <= 1'b0;
            req_addr     <= mem_addr;
            req_wdata    <= mem_wdata;
            req_wstrb    <= mem_wstrb;
        end else if (sdram_req_fire) begin
            sdram_req_sent <= 1'b1;
        end
    end
end

endmodule
