// print-lite：裸机最小输出接口。
// 第一版只提供 puts / print_hex / print_dec，薄封装现有 UART 驱动，
// 不引入完整 printf。行为与 drivers/uart.c 的对应函数一致。
#ifndef RT_PRINT_H
#define RT_PRINT_H

// 输出字符串（不自动追加换行）。
void rt_puts(const char *str);

// 以 "0x" 开头输出 32 位十六进制。
void rt_print_hex(unsigned int value);

// 输出无符号十进制。
void rt_print_dec(unsigned int value);

#endif
