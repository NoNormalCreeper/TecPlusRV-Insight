// TinyBus 的最小 MMIO 译码器。
// 这个模块不保存状态，只把 CPU 发来的地址译码成各外设的 select 信号，
// 并在读操作时把被选中外设的数据 mux 回 CPU。
`include "tinybus_defs.vh"

module tinybus_decode (
    input         valid,
    input  [31:0] addr,
    input  [31:0] wdata,
    input  [3:0]  wstrb,
    input  [31:0] gpio_key_rdata,
    input  [31:0] uart_status_rdata,
    input  [31:0] cycle_rdata,
    input  [31:0] instret_rdata,
    input  [31:0] accel_rdata,
    output reg [31:0] rdata,
    output            ready,
    output            write_en,
    output            gpio_led_sel,
    output            gpio_key_sel,
    output            uart_data_sel,
    output            uart_status_sel,
    output            cycle_sel,
    output            instret_sel,
    output            test_exit_sel,
    output            accel_sel,
    output [31:0]     write_data
);

// 每个 *_sel 表示本周期地址命中了对应外设。
// 目前 TinyBus 是单周期占位协议，所以 valid 一来就直接 ready。
assign gpio_led_sel = valid && (addr == `TINYBUS_ADDR_GPIO_LED);
assign gpio_key_sel = valid && (addr == `TINYBUS_ADDR_GPIO_KEY);
assign uart_data_sel = valid && (addr == `TINYBUS_ADDR_UART_DATA);
assign uart_status_sel = valid && (addr == `TINYBUS_ADDR_UART_STATUS);
assign cycle_sel = valid && (addr == `TINYBUS_ADDR_CYCLE);
assign instret_sel = valid && (addr == `TINYBUS_ADDR_INSTRET);
assign test_exit_sel = valid && (addr == `TINYBUS_ADDR_TEST_EXIT);
assign accel_sel = valid && (addr[31:28] == 4'h2);
assign write_en = valid && (wstrb != 4'b0000);
assign write_data = wdata;
assign ready = valid;

always @(*) begin
    // 未实现地址默认读 0。这样早期 bring-up 不会因为空洞地址产生 X。
    rdata = 32'h0000_0000;

    // 当前只有少量占位外设支持读回。
    if (gpio_key_sel) begin
        rdata = gpio_key_rdata;
    end else if (uart_status_sel) begin
        rdata = uart_status_rdata;
    end else if (cycle_sel) begin
        rdata = cycle_rdata;
    end else if (instret_sel) begin
        rdata = instret_rdata;
    end else if (accel_sel) begin
        rdata = accel_rdata;
    end
end

endmodule
