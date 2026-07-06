#ifndef MMIO_H
#define MMIO_H

#define MMIO32(addr) (*(volatile unsigned int *)(addr))

#define TINYBUS_GPIO_LED     0x10000000u
#define TINYBUS_GPIO_KEY     0x10000004u
#define TINYBUS_UART_DATA    0x10000010u
#define TINYBUS_UART_STATUS  0x10000014u
#define TINYBUS_CYCLE        0x10000020u
#define TINYBUS_INSTRET      0x10000024u
#define TINYBUS_TEST_EXIT    0x10000030u
#define TINYBUS_ACCEL_BASE   0x20000000u
#define TINYBUS_SDRAM_BASE   0x80000000u

static inline void mmio_write(unsigned int addr, unsigned int value)
{
    MMIO32(addr) = value;
}

static inline unsigned int mmio_read(unsigned int addr)
{
    return MMIO32(addr);
}

#endif

