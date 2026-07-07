// UART 发送驱动的最小接口。
// 当前只支持阻塞式发送字符/字符串，足够用于 bring-up 打印。
#ifndef UART_H
#define UART_H

void uart_putc(char ch);
void uart_puts(const char *str);
// 以 "0x" 开头打印 32 位十六进制值，调试/打印错误码时用。
void uart_put_hex(unsigned int value);
// 打印无符号十进制值，性能数据（cycles / instret / CPI）给人看时用。
void uart_put_dec(unsigned int value);
// 阻塞直到 TX 空闲，确保最后一个字符真正发完（退出/复位前收尾用）。
void uart_flush(void);

#endif
