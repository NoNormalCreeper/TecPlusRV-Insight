// 最小 bare-metal 应用：同一份源码可普通运行，也可用 firmware-debug 调试。
#include "drivers/gpio.h"
#include "runtime/debug.h"

volatile unsigned int hello_value;

int main(void)
{
    hello_value = 0x12345678u;
    gpio_write_led(1u);
    DEBUG_BREAK();

    for (;;) {
        hello_value++;
    }
}
