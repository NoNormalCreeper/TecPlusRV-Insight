// TinyBus MMIO 访问辅助。
// 这里是软件侧 memory map，地址必须和 rtl/soc/tinybus_defs.vh 保持一致。
// volatile 防止编译器把硬件寄存器读写优化掉。
#ifndef MMIO_H
#define MMIO_H

#define MMIO32(addr) (*(volatile unsigned int *)(addr))

// TinyBus 外设地址。0x1000_0000 是基础外设区，0x2000_0000 预留给加速器。
#define TINYBUS_GPIO_LED     0x10000000u
#define TINYBUS_GPIO_KEY     0x10000004u
#define TINYBUS_UART_DATA    0x10000010u
#define TINYBUS_UART_STATUS  0x10000014u
#define TINYBUS_CYCLE        0x10000020u
#define TINYBUS_INSTRET      0x10000024u
#define TINYBUS_TEST_EXIT    0x10000030u
#define TINYBUS_TRAFFIC_DATA 0x10000040u
#define TINYBUS_ACCEL_BASE   0x20000000u
#define TINYBUS_SDRAM_BASE   0x80000000u

static inline void mmio_write(unsigned int addr, unsigned int value)
{
    // 裸机环境直接把整数地址当作硬件寄存器地址访问。
    MMIO32(addr) = value;
}

static inline unsigned int mmio_read(unsigned int addr)
{
    return MMIO32(addr);
}

#endif
