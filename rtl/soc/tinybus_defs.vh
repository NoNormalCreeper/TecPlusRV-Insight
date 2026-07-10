// TinyBus 的统一地址表。
// RTL 和 firmware 都要使用同一套 memory map；这里是硬件侧常量，
// firmware/drivers/mmio.h 是软件侧镜像，改地址时两边必须一起改。
`ifndef TINYBUS_DEFS_VH
`define TINYBUS_DEFS_VH

`define TINYBUS_ADDR_GPIO_LED     32'h1000_0000
`define TINYBUS_ADDR_GPIO_KEY     32'h1000_0004
`define TINYBUS_ADDR_UART_DATA    32'h1000_0010
`define TINYBUS_ADDR_UART_STATUS  32'h1000_0014
`define TINYBUS_ADDR_CYCLE        32'h1000_0020
`define TINYBUS_ADDR_INSTRET      32'h1000_0024
`define TINYBUS_ADDR_TEST_EXIT    32'h1000_0030
`define TINYBUS_ADDR_TRAFFIC_DATA 32'h1000_0040
`define TINYBUS_ADDR_BUZZER_CTRL  32'h1000_0050
`define TINYBUS_ADDR_BUZZER_PERIOD 32'h1000_0054
`define TINYBUS_ADDR_VGA_STATUS    32'h1000_0060
`define TINYBUS_ADDR_VGA_TILE_BASE 32'h1001_0000
// 40 * 30 个 byte tile，共 300 个 packed word。窗口严格收紧，避免 9-bit
// tile_addr 在 4 KiB 空洞区域发生截断别名。
`define TINYBUS_VGA_TILE_BYTES     32'h0000_04b0
`define TINYBUS_ADDR_ACCEL_BASE   32'h2000_0000
`define TINYBUS_ADDR_SDRAM_BASE   32'h8000_0000

`endif
