// TEC-PLUS MiniSoC board top.
// This is the ISE top-level wrapper: only real board pins leave the FPGA.
// PicoRV32 buses stay internal and are decoded into BRAM plus TinyBus MMIO.
`include "tinybus_defs.vh"

module tecplus_minisoc_top #(
    parameter integer CLK_FREQ = 50000000,
    parameter integer UART_BAUD = 9600,
    parameter integer BRAM_ADDR_WIDTH = 14,
    parameter BRAM_INIT_FILE = "firmware/build/firmware.mem"
) (
    input        clk,
    input        reset,
    input  [3:0] key,
    output reg [3:0] led,
    input        uart_rxd,
    output       uart_txd
);

localparam [31:0] BRAM_BYTES = (32'd1 << BRAM_ADDR_WIDTH) * 32'd4;

wire resetn;
wire rst;

wire        mem_valid;
wire        mem_instr;
reg         mem_ready;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire [3:0]  mem_wstrb;
reg  [31:0] mem_rdata;

wire        start_req;
wire        start_is_bram;
wire        bram_en;
wire [BRAM_ADDR_WIDTH-1:0] bram_addr;
wire [31:0] bram_rdata;

reg         pending;
reg         req_is_bram;
reg  [31:0] req_addr;
reg  [31:0] req_wdata;
reg  [3:0]  req_wstrb;

wire [31:0] gpio_key_rdata;
wire [31:0] uart_status_rdata;
wire [31:0] cycle_rdata;
wire [31:0] instret_rdata;
wire [31:0] mmio_rdata;
wire        mmio_write_en;
wire        gpio_led_sel;
wire        uart_data_sel;
wire        test_exit_sel;
wire        uart_ready;
wire        uart_fire;
wire        test_exit_write;
wire        mmio_stall;
wire        respond;

reg [31:0] cycle_count;
reg [31:0] instret_count;

wire unused_uart_rxd;
wire unused_mem_instr;

wire        test_exited;
wire [31:0] test_exit_code;

assign resetn = reset;
assign rst = !reset;
assign unused_uart_rxd = uart_rxd;
assign unused_mem_instr = mem_instr;

assign start_req = mem_valid && !pending && !mem_ready;
assign start_is_bram = (mem_addr < BRAM_BYTES);
assign bram_en = start_req && start_is_bram;
assign bram_addr = mem_addr[BRAM_ADDR_WIDTH+1:2];

assign gpio_key_rdata = {28'h0000000, key};
assign uart_status_rdata = {31'h00000000, uart_ready};
assign cycle_rdata = cycle_count;
assign instret_rdata = instret_count;

assign mmio_stall = pending && !req_is_bram && uart_data_sel && mmio_write_en && !uart_ready;
assign respond = pending && !mmio_stall;
assign uart_fire = respond && !req_is_bram && uart_data_sel && mmio_write_en;
assign test_exit_write = respond && !req_is_bram && test_exit_sel && mmio_write_en;

picorv32 #(
    .ENABLE_COUNTERS(0),
    .ENABLE_COUNTERS64(0),
    .ENABLE_REGS_DUALPORT(0),
    .TWO_STAGE_SHIFT(1),
    .BARREL_SHIFTER(0),
    .COMPRESSED_ISA(0),
    .ENABLE_PCPI(0),
    .ENABLE_MUL(0),
    .ENABLE_FAST_MUL(0),
    .ENABLE_DIV(0),
    .ENABLE_IRQ(0),
    .ENABLE_TRACE(0),
    .PROGADDR_RESET(32'h0000_0000),
    .STACKADDR(BRAM_BYTES)
) u_cpu (
    .clk(clk),
    .resetn(resetn),
    .trap(),
    .mem_valid(mem_valid),
    .mem_instr(mem_instr),
    .mem_ready(mem_ready),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(mem_rdata),
    .pcpi_wr(1'b0),
    .pcpi_rd(32'h0000_0000),
    .pcpi_wait(1'b0),
    .pcpi_ready(1'b0),
    .irq(32'h0000_0000),
    .eoi(),
    .trace_valid(),
    .trace_data()
);

bram #(
    .ADDR_WIDTH(BRAM_ADDR_WIDTH),
    .USE_INIT_FILE(1),
    .INIT_FILE(BRAM_INIT_FILE)
) u_bram (
    .clk(clk),
    .en(bram_en),
    .addr(bram_addr),
    .wdata(mem_wdata),
    .wstrb(mem_wstrb),
    .rdata(bram_rdata)
);

tinybus_decode u_decode (
    .valid(pending && !req_is_bram),
    .addr(req_addr),
    .wdata(req_wdata),
    .wstrb(req_wstrb),
    .gpio_key_rdata(gpio_key_rdata),
    .uart_status_rdata(uart_status_rdata),
    .cycle_rdata(cycle_rdata),
    .instret_rdata(instret_rdata),
    .accel_rdata(32'h0000_0000),
    .rdata(mmio_rdata),
    .ready(),
    .write_en(mmio_write_en),
    .gpio_led_sel(gpio_led_sel),
    .gpio_key_sel(),
    .uart_data_sel(uart_data_sel),
    .uart_status_sel(),
    .cycle_sel(),
    .instret_sel(),
    .test_exit_sel(test_exit_sel),
    .accel_sel(),
    .write_data()
);

uart_tx #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD(UART_BAUD)
) u_uart_tx (
    .clk(clk),
    .reset(rst),
    .valid(uart_fire),
    .data_in(req_wdata[7:0]),
    .ready(uart_ready),
    .txd(uart_txd)
);

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
        req_is_bram <= 1'b0;
        req_addr <= 32'h0000_0000;
        req_wdata <= 32'h0000_0000;
        req_wstrb <= 4'b0000;
        mem_ready <= 1'b0;
        mem_rdata <= 32'h0000_0000;
        led <= 4'h0;
        cycle_count <= 32'h0000_0000;
        instret_count <= 32'h0000_0000;
    end else begin
        mem_ready <= 1'b0;
        cycle_count <= cycle_count + 32'd1;

        if (respond) begin
            pending <= 1'b0;
            mem_ready <= 1'b1;
            mem_rdata <= req_is_bram ? bram_rdata : mmio_rdata;

            if (!req_is_bram && gpio_led_sel && mmio_write_en) begin
                led <= req_wdata[3:0];
            end

            if (req_is_bram && req_wstrb == 4'b0000) begin
                instret_count <= instret_count + 32'd1;
            end
        end else if (start_req) begin
            pending <= 1'b1;
            req_is_bram <= start_is_bram;
            req_addr <= mem_addr;
            req_wdata <= mem_wdata;
            req_wstrb <= mem_wstrb;
        end
    end
end

endmodule
