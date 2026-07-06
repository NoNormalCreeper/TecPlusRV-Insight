// GPIO MMIO 驱动实现。
// 这里不做缓存和状态保存，每次调用都直接访问硬件寄存器。
#include "gpio.h"
#include "mmio.h"

void gpio_write_led(unsigned int value)
{
    mmio_write(TINYBUS_GPIO_LED, value);
}

unsigned int gpio_read_key(void)
{
    return mmio_read(TINYBUS_GPIO_KEY);
}
