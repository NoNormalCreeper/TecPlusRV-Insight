// UART 发送驱动的最小接口。
// 当前只支持阻塞式发送字符/字符串，足够用于 bring-up 打印。
#ifndef UART_H
#define UART_H

void uart_putc(char ch);
void uart_puts(const char *str);

#endif
