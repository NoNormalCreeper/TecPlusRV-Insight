#ifndef TESTLIB_H
#define TESTLIB_H

#include "../drivers/gpio.h"
#include "../drivers/mmio.h"
#include "../drivers/uart.h"

static inline void test_banner(const char *name)
{
    gpio_write_led(0x1u);
    uart_puts(name);
    uart_puts("\n");
}

static inline void test_fail(unsigned int code)
{
    gpio_write_led(code & 0xfu);
    mmio_write(TINYBUS_TEST_EXIT, code);
    for (;;) {
    }
}

static inline void test_expect(int condition, unsigned int code)
{
    if (!condition) {
        test_fail(code);
    }
}

static inline void test_pass(void)
{
    gpio_write_led(0x5u);
    mmio_write(TINYBUS_TEST_EXIT, 1u);
    for (;;) {
    }
}

static inline unsigned int test_read_cycle(void)
{
    return mmio_read(TINYBUS_CYCLE);
}

static inline unsigned int test_read_instret(void)
{
    return mmio_read(TINYBUS_INSTRET);
}

static inline unsigned int test_read_mem_wait(void)
{
    return mmio_read(TINYBUS_MEM_WAIT);
}

#endif
