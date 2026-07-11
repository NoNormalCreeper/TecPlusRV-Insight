// tinybus_decode 的组合逻辑仿真。
// 重点验证地址命中、写使能、读数据 mux，以及 SDRAM 地址不会误触发。
`timescale 1ns/1ps

`include "tinybus_defs.vh"

module tb_tinybus_decode;

reg        valid;
reg [31:0] addr;
reg [31:0] wdata;
reg [3:0]  wstrb;
reg [31:0] gpio_key_rdata;
reg [31:0] uart_data_rdata;
reg [31:0] uart_status_rdata;
reg [31:0] cycle_rdata;
reg [31:0] instret_rdata;
reg [31:0] mem_wait_rdata;
reg [31:0] traffic_rdata;
reg [31:0] buzzer_ctrl_rdata;
reg [31:0] buzzer_period_rdata;
reg [31:0] vga_status_rdata;
reg [31:0] mtime_lo_rdata;
reg [31:0] mtime_hi_rdata;
reg [31:0] mtimecmp_lo_rdata;
reg [31:0] mtimecmp_hi_rdata;
reg [31:0] accel_rdata;

wire [31:0] rdata;
wire        ready;
wire        write_en;
wire        gpio_led_sel;
wire        gpio_key_sel;
wire        uart_data_sel;
wire        uart_status_sel;
wire        cycle_sel;
wire        instret_sel;
wire        mem_wait_sel;
wire        test_exit_sel;
wire        traffic_sel;
wire        buzzer_ctrl_sel;
wire        buzzer_period_sel;
wire        vga_status_sel;
wire        vga_tile_sel;
wire        vga_fb_sel;
wire        mtime_lo_sel;
wire        mtime_hi_sel;
wire        mtimecmp_lo_sel;
wire        mtimecmp_hi_sel;
wire        accel_sel;
wire [31:0] write_data;
wire [3:0] timer_sel = {
    mtimecmp_hi_sel, mtimecmp_lo_sel, mtime_hi_sel, mtime_lo_sel
};

tinybus_decode dut (
    .valid(valid),
    .addr(addr),
    .wdata(wdata),
    .wstrb(wstrb),
    .gpio_key_rdata(gpio_key_rdata),
    .uart_data_rdata(uart_data_rdata),
    .uart_status_rdata(uart_status_rdata),
    .cycle_rdata(cycle_rdata),
    .instret_rdata(instret_rdata),
    .mem_wait_rdata(mem_wait_rdata),
    .traffic_rdata(traffic_rdata),
    .buzzer_ctrl_rdata(buzzer_ctrl_rdata),
    .buzzer_period_rdata(buzzer_period_rdata),
    .vga_status_rdata(vga_status_rdata),
    .mtime_lo_rdata(mtime_lo_rdata),
    .mtime_hi_rdata(mtime_hi_rdata),
    .mtimecmp_lo_rdata(mtimecmp_lo_rdata),
    .mtimecmp_hi_rdata(mtimecmp_hi_rdata),
    .accel_rdata(accel_rdata),
    .rdata(rdata),
    .ready(ready),
    .write_en(write_en),
    .gpio_led_sel(gpio_led_sel),
    .gpio_key_sel(gpio_key_sel),
    .uart_data_sel(uart_data_sel),
    .uart_status_sel(uart_status_sel),
    .cycle_sel(cycle_sel),
    .instret_sel(instret_sel),
    .mem_wait_sel(mem_wait_sel),
    .test_exit_sel(test_exit_sel),
    .traffic_sel(traffic_sel),
    .buzzer_ctrl_sel(buzzer_ctrl_sel),
    .buzzer_period_sel(buzzer_period_sel),
    .vga_status_sel(vga_status_sel),
    .vga_tile_sel(vga_tile_sel),
    .vga_fb_sel(vga_fb_sel),
    .mtime_lo_sel(mtime_lo_sel),
    .mtime_hi_sel(mtime_hi_sel),
    .mtimecmp_lo_sel(mtimecmp_lo_sel),
    .mtimecmp_hi_sel(mtimecmp_hi_sel),
    .accel_sel(accel_sel),
    .write_data(write_data)
);

initial begin
    valid = 1'b0;
    addr = 32'h0000_0000;
    wdata = 32'hDEAD_BEEF;
    wstrb = 4'b0000;
    gpio_key_rdata = 32'h0000_000F;
    uart_data_rdata = 32'h0000_005A;
    uart_status_rdata = 32'h0000_0001;
    cycle_rdata = 32'h1234_5678;
    instret_rdata = 32'h8765_4321;
    mem_wait_rdata = 32'h0000_00a5;
    traffic_rdata = 32'h0000_0A55;
    buzzer_ctrl_rdata = 32'h0000_0001;
    buzzer_period_rdata = 32'h0000_1388;
    vga_status_rdata = 32'h1234_0003;
    mtime_lo_rdata = 32'h0123_4567;
    mtime_hi_rdata = 32'h89ab_cdef;
    mtimecmp_lo_rdata = 32'h7654_3210;
    mtimecmp_hi_rdata = 32'hfedc_ba98;
    accel_rdata = 32'hCAFE_BABE;

    #1;
    if (ready !== 1'b0 || write_en !== 1'b0) begin
        $display("FAIL: valid=0 时 ready/write_en 应为 0");
        $finish;
    end

    valid = 1'b1;
    addr = `TINYBUS_ADDR_GPIO_KEY;
    #1;
    if (!gpio_key_sel || rdata !== gpio_key_rdata) begin
        $display("FAIL: GPIO KEY 译码或读回错误");
        $finish;
    end

    addr = `TINYBUS_ADDR_UART_DATA;
    #1;
    if (!uart_data_sel || write_en || rdata !== uart_data_rdata) begin
        $display("FAIL: UART DATA 读译码错误");
        $finish;
    end

    addr = `TINYBUS_ADDR_UART_STATUS;
    #1;
    if (!uart_status_sel || rdata !== uart_status_rdata) begin
        $display("FAIL: UART STATUS 译码或读回错误");
        $finish;
    end


    addr = `TINYBUS_ADDR_MEM_WAIT;
    #1;
    if (!mem_wait_sel || rdata !== mem_wait_rdata) begin
        $display("FAIL: MEM_WAIT 译码或读回错误");
        $finish;
    end

    addr = `TINYBUS_ADDR_TEST_EXIT;
    wstrb = 4'b1111;
    #1;
    if (!test_exit_sel || !write_en || write_data !== wdata) begin
        $display("FAIL: TEST_EXIT 写路径译码错误");
        $finish;
    end

    addr = `TINYBUS_ADDR_TRAFFIC_DATA;
    wstrb = 4'b0000;
    #1;
    if (!traffic_sel || write_en || rdata !== traffic_rdata) begin
        $display("FAIL: TRAFFIC DATA 译码或读回错误");
        $finish;
    end

    addr = `TINYBUS_ADDR_BUZZER_CTRL;
    #1;
    if (!buzzer_ctrl_sel || rdata !== buzzer_ctrl_rdata) begin
        $display("FAIL: BUZZER CTRL 译码或读回错误");
        $finish;
    end

    addr = `TINYBUS_ADDR_BUZZER_PERIOD;
    #1;
    if (!buzzer_period_sel || rdata !== buzzer_period_rdata) begin
        $display("FAIL: BUZZER PERIOD 译码或读回错误");
        $finish;
    end


    addr = `TINYBUS_ADDR_VGA_STATUS;
    #1;
    if (!vga_status_sel || rdata !== vga_status_rdata) begin
        $display("FAIL: VGA STATUS 译码或读回错误");
        $finish;
    end

    addr = `TINYBUS_ADDR_MTIME_LO;
    #1;
    if (timer_sel !== 4'b0001 || rdata !== mtime_lo_rdata ||
        vga_status_sel || vga_tile_sel || accel_sel) begin
        $display("FAIL: MTIME_LO 译码、读回或窗口隔离错误");
        $finish;
    end
    wstrb = 4'b1111;
    #1;
    if (timer_sel !== 4'b0001 || !write_en) begin
        $display("FAIL: MTIME_LO 写 select 错误");
        $finish;
    end

    addr = `TINYBUS_ADDR_MTIME_HI;
    wstrb = 4'b0000;
    #1;
    if (timer_sel !== 4'b0010 || rdata !== mtime_hi_rdata ||
        vga_status_sel || vga_tile_sel || accel_sel) begin
        $display("FAIL: MTIME_HI 译码、读回或窗口隔离错误");
        $finish;
    end
    wstrb = 4'b1111;
    #1;
    if (timer_sel !== 4'b0010 || !write_en) begin
        $display("FAIL: MTIME_HI 写 select 错误");
        $finish;
    end

    addr = `TINYBUS_ADDR_MTIMECMP_LO;
    wstrb = 4'b0000;
    #1;
    if (timer_sel !== 4'b0100 || rdata !== mtimecmp_lo_rdata ||
        vga_status_sel || vga_tile_sel || accel_sel) begin
        $display("FAIL: MTIMECMP_LO 译码、读回或窗口隔离错误");
        $finish;
    end
    wstrb = 4'b1111;
    #1;
    if (timer_sel !== 4'b0100 || !write_en) begin
        $display("FAIL: MTIMECMP_LO 写 select 错误");
        $finish;
    end

    addr = `TINYBUS_ADDR_MTIMECMP_HI;
    wstrb = 4'b0000;
    #1;
    if (timer_sel !== 4'b1000 || rdata !== mtimecmp_hi_rdata ||
        vga_status_sel || vga_tile_sel || accel_sel) begin
        $display("FAIL: MTIMECMP_HI 译码、读回或窗口隔离错误");
        $finish;
    end
    wstrb = 4'b1111;
    #1;
    if (timer_sel !== 4'b1000 || !write_en) begin
        $display("FAIL: MTIMECMP_HI 写 select 错误");
        $finish;
    end

    addr = `TINYBUS_ADDR_VGA_TILE_BASE + 32'd1196;
    wstrb = 4'b0000;
    #1;
    if (vga_tile_sel || rdata !== 32'h0000_0000) begin
        $display("FAIL: VGA tile 读访问应返回 0 且不命中 write-only window");
        $finish;
    end

    wstrb = 4'b1111;
    #1;
    if (!vga_tile_sel || !write_en || write_data !== wdata) begin
        $display("FAIL: VGA tile 写访问译码错误");
        $finish;
    end

    addr = `TINYBUS_ADDR_VGA_FB_BASE + `TINYBUS_VGA_FB_BYTES - 4;
    #1;
    if (!vga_fb_sel || !vga_tile_sel) begin
        $display("FAIL: VGA 1bpp framebuffer 末 word 未命中");
        $finish;
    end

    addr = `TINYBUS_ADDR_VGA_FB_BASE + `TINYBUS_VGA_FB_BYTES;
    #1;
    if (vga_fb_sel || !vga_tile_sel) begin
        $display("FAIL: VGA framebuffer 上界错误或破坏旧 tile window");
        $finish;
    end

    addr = `TINYBUS_ADDR_VGA_TILE_BASE + `TINYBUS_VGA_TILE_BYTES;
    wstrb = 4'b0000;
    #1;
    if (vga_tile_sel) begin
        $display("FAIL: VGA tile window 上界发生地址别名");
        $finish;
    end

    addr = 32'h2000_0100;
    wstrb = 4'b0000;
    #1;
    if (!accel_sel || rdata !== accel_rdata) begin
        $display("FAIL: ACCEL 区域译码或读回错误");
        $finish;
    end

    // 遍历 SDRAM 基地址及边界内一个地址，确保没有任何选择信号激活
    addr = `TINYBUS_ADDR_SDRAM_BASE;  // 0x8000_0000
    #1;
    if (gpio_led_sel || gpio_key_sel || uart_data_sel || uart_status_sel ||
        cycle_sel || instret_sel || mem_wait_sel || test_exit_sel || traffic_sel ||
        buzzer_ctrl_sel || buzzer_period_sel || vga_status_sel || vga_tile_sel ||
        (|timer_sel) || accel_sel) begin
        $display("FAIL: SDRAM 地址 %h 误触发了 TinyBus 选择信号", addr);
        $finish;
    end
    if (write_en !== 1'b0) begin
        $display("FAIL: SDRAM 地址 %h 错误地置位 write_en", addr);
        $finish;
    end
    // ready 应为 1（表示已解码，但未命中任何已定义外设）
    if (ready !== 1'b1) begin
        $display("FAIL: SDRAM 地址 %h 应返回 ready=1", addr);
        $finish;
    end

    addr = `TINYBUS_ADDR_SDRAM_BASE + 32'h0000_1000;  // 范围内任意地址
    #1;
    if (gpio_led_sel || gpio_key_sel || uart_data_sel || uart_status_sel ||
        cycle_sel || instret_sel || mem_wait_sel || test_exit_sel || traffic_sel ||
        buzzer_ctrl_sel || buzzer_period_sel || vga_status_sel || vga_tile_sel ||
        (|timer_sel) || accel_sel) begin
        $display("FAIL: SDRAM 地址 %h 误触发了 TinyBus 选择信号", addr);
        $finish;
    end
    if (write_en !== 1'b0) begin
        $display("FAIL: SDRAM 地址 %h 错误地置位 write_en", addr);
        $finish;
    end
    if (ready !== 1'b1) begin
        $display("FAIL: SDRAM 地址 %h 应返回 ready=1", addr);
        $finish;
    end

    $display("PASS: tinybus_decode 译码语义及 SDRAM 地址隔离均符合预期");
    $finish;
end

endmodule
