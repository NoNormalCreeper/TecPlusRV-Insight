// TEC-PLUS MiniSoC board top.
// This is the ISE top-level wrapper: only real board pins leave the FPGA.
// PicoRV32 buses stay internal and are decoded into BRAM plus TinyBus MMIO.
`include "tinybus_defs.vh"

module tecplus_minisoc_top #(
    parameter integer CLK_FREQ = 50000000,
    parameter integer UART_BAUD = 9600,
    parameter integer CPU_IMPL = 0,
    parameter integer BRAM_ADDR_WIDTH = 14,
    parameter BRAM_INIT_FILE = "firmware/build/firmware.mem"
) (
    input        clk,
    input        reset,
    input  [3:0] key,
    output reg [3:0] led,
    input        uart_rxd,
    output       uart_txd,
    output [11:0] tl,
    output       spk
);

localparam [31:0] BRAM_BYTES = (32'd1 << BRAM_ADDR_WIDTH) * 32'd4;

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
wire        start_is_bram;
wire        bram_en;
wire [BRAM_ADDR_WIDTH-1:0] bram_addr;
wire [31:0] bram_data_rdata;

wire        ifetch_is_bram;
wire        ifetch_en;
wire [BRAM_ADDR_WIDTH-1:0] ifetch_bram_addr;
wire [31:0] ifetch_bram_rdata;

reg         pending;
reg         ifetch_pending;
reg         req_is_bram;
reg         req_is_replay;
reg  [31:0] req_addr;
reg  [31:0] req_wdata;
reg  [3:0]  req_wstrb;
reg         last_req_valid;
reg  [31:0] last_req_addr;
reg  [31:0] last_req_wdata;
reg  [3:0]  last_req_wstrb;

wire [31:0] gpio_key_rdata;
wire [31:0] uart_data_rdata;
wire [31:0] uart_status_rdata;
wire [31:0] cycle_rdata;
wire [31:0] instret_rdata;
wire [31:0] traffic_rdata;
wire [31:0] buzzer_ctrl_rdata;
wire [31:0] buzzer_period_rdata;
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
wire        uart_tx_ready;
wire        uart_fire;
wire [7:0]  uart_rx_data;
wire        uart_rx_valid;
wire        uart_rx_overrun;
wire        uart_rx_framing_error;
wire        uart_rx_consume;
wire        uart_overrun_clear;
wire        uart_framing_error_clear;
wire        test_exit_write;
wire        traffic_write;
wire        buzzer_ctrl_write;
wire        buzzer_period_write;
wire        buzzer_enabled;
wire [31:0] buzzer_half_period;
wire        mmio_stall;
wire        respond;

wire        test_exited;
wire [31:0] test_exit_code;
wire        same_as_last_req;

assign resetn = reset;
assign rst = !reset;

assign start_req = mem_valid && !pending && !mem_ready;
assign start_is_bram = (mem_addr < BRAM_BYTES);
assign bram_en = start_req && start_is_bram;
assign bram_addr = mem_addr[BRAM_ADDR_WIDTH+1:2];
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

assign same_as_last_req =
    last_req_valid &&
    (mem_addr == last_req_addr) &&
    (mem_wdata == last_req_wdata) &&
    (mem_wstrb == last_req_wstrb);

assign mmio_stall = pending && !req_is_bram && !req_is_replay && uart_data_sel && mmio_write_en && !uart_tx_ready;
assign respond = pending && !mmio_stall;
assign uart_fire = respond && !req_is_bram && !req_is_replay && uart_data_sel && mmio_write_en;
assign uart_rx_consume = respond && !req_is_bram && !req_is_replay && uart_data_sel && !mmio_write_en;
assign uart_overrun_clear =
    respond && !req_is_bram && !req_is_replay &&
    uart_status_sel && mmio_write_en && req_wdata[2];
assign uart_framing_error_clear =
    respond && !req_is_bram && !req_is_replay &&
    uart_status_sel && mmio_write_en && req_wdata[3];
assign test_exit_write = respond && !req_is_bram && !req_is_replay && test_exit_sel && mmio_write_en;
assign traffic_write = respond && !req_is_bram && !req_is_replay && traffic_sel && mmio_write_en;
assign buzzer_ctrl_write = respond && !req_is_bram && !req_is_replay && buzzer_ctrl_sel && mmio_write_en;
assign buzzer_period_write = respond && !req_is_bram && !req_is_replay && buzzer_period_sel && mmio_write_en;

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
    .wdata_a(mem_wdata),
    .wstrb_a(mem_wstrb),
    .rdata_a(bram_data_rdata),
    .clk_b(clk),
    .en_b(ifetch_en),
    .addr_b(ifetch_bram_addr),
    .rdata_b(ifetch_bram_rdata)
);

tinybus_decode u_decode (
    .valid(pending && !req_is_bram),
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
    .data_ready(uart_rx_consume),
    .clear_overrun(uart_overrun_clear),
    .clear_framing_error(uart_framing_error_clear),
    .data_out(uart_rx_data),
    .data_valid(uart_rx_valid),
    .overrun(uart_rx_overrun),
    .framing_error(uart_rx_framing_error)
);

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
        req_is_replay <= 1'b0;
        req_addr <= 32'h0000_0000;
        req_wdata <= 32'h0000_0000;
        req_wstrb <= 4'b0000;
        last_req_valid <= 1'b0;
        last_req_addr <= 32'h0000_0000;
        last_req_wdata <= 32'h0000_0000;
        last_req_wstrb <= 4'b0000;
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
            mem_rdata <= req_is_bram ? bram_data_rdata : mmio_rdata;
            last_req_valid <= 1'b1;
            last_req_addr <= req_addr;
            last_req_wdata <= req_wdata;
            last_req_wstrb <= req_wstrb;

            if (!req_is_bram && !req_is_replay && gpio_led_sel && mmio_write_en) begin
                led <= req_wdata[3:0];
            end
        end else if (start_req) begin
            pending <= 1'b1;
            req_is_bram <= start_is_bram;
            req_is_replay <= same_as_last_req;
            req_addr <= mem_addr;
            req_wdata <= mem_wdata;
            req_wstrb <= mem_wstrb;
        end
    end
end

endmodule
