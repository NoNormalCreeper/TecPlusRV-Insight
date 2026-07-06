// GPIO 驱动的最小接口。
// 当前只暴露 LED 写和 KEY 读，底层地址在 mmio.h 中定义。
#ifndef GPIO_H
#define GPIO_H

void gpio_write_led(unsigned int value);
unsigned int gpio_read_key(void);

#endif
