// print-lite 实现：薄封装 drivers/uart.c，复用已验证的输出逻辑，
// 避免重复实现十六进制/十进制格式化。
#include "rt_print.h"
#include "../drivers/uart.h"

void rt_puts(const char *str)
{
    uart_puts(str);
}

void rt_print_hex(unsigned int value)
{
    uart_put_hex(value);
}

void rt_print_dec(unsigned int value)
{
    uart_put_dec(value);
}
