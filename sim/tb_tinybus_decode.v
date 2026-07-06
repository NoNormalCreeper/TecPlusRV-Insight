// tinybus_decode 的组合逻辑仿真。
// 重点验证地址命中、写使能、读数据 mux，而不是完整 CPU 总线时序。
`timescale 1ns/1ps

`include "tinybus_defs.vh"

module tb_tinybus_decode;

reg        valid;
reg [31:0] addr;
reg [31:0] wdata;
reg [3:0]  wstrb;
reg [31:0] gpio_key_rdata;
reg [31:0] uart_status_rdata;
reg [31:0] cycle_rdata;
reg [31:0] instret_rdata;
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
wire        test_exit_sel;
wire        accel_sel;
wire [31:0] write_data;

tinybus_decode dut (
    .valid(valid),
    .addr(addr),
    .wdata(wdata),
    .wstrb(wstrb),
    .gpio_key_rdata(gpio_key_rdata),
    .uart_status_rdata(uart_status_rdata),
    .cycle_rdata(cycle_rdata),
    .instret_rdata(instret_rdata),
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
    .test_exit_sel(test_exit_sel),
    .accel_sel(accel_sel),
    .write_data(write_data)
);

initial begin
    valid = 1'b0;
    addr = 32'h0000_0000;
    wdata = 32'hDEAD_BEEF;
    wstrb = 4'b0000;
    gpio_key_rdata = 32'h0000_000F;
    uart_status_rdata = 32'h0000_0001;
    cycle_rdata = 32'h1234_5678;
    instret_rdata = 32'h8765_4321;
    accel_rdata = 32'hCAFE_BABE;

    #1;
    if (ready !== 1'b0 || write_en !== 1'b0) begin
        $display("FAIL: valid=0 时 ready/write_en 应为 0");
        $finish;
    end

    valid = 1'b1;
    addr = `TINYBUS_ADDR_GPIO_KEY;
    #1;
    // 组合逻辑需要一个 delta 时间稳定，所以这里用 #1 后再检查。
    if (!gpio_key_sel || rdata !== gpio_key_rdata) begin
        $display("FAIL: GPIO KEY 译码或读回错误");
        $finish;
    end

    addr = `TINYBUS_ADDR_UART_STATUS;
    #1;
    if (!uart_status_sel || rdata !== uart_status_rdata) begin
        $display("FAIL: UART STATUS 译码或读回错误");
        $finish;
    end

    addr = `TINYBUS_ADDR_TEST_EXIT;
    wstrb = 4'b1111;
    #1;
    if (!test_exit_sel || !write_en || write_data !== wdata) begin
        $display("FAIL: TEST_EXIT 写路径译码错误");
        $finish;
    end

    addr = 32'h2000_0100;
    wstrb = 4'b0000;
    #1;
    if (!accel_sel || rdata !== accel_rdata) begin
        $display("FAIL: ACCEL 区域译码或读回错误");
        $finish;
    end

    $display("PASS: tinybus_decode 基本译码语义符合预期");
    $finish;
end

endmodule
