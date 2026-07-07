// UART TX MMIO 驱动实现。
// 发送前轮询 TX_READY，硬件准备好后再写 DATA 寄存器。
#include "mmio.h"
#include "uart.h"

#define UART_STATUS_TX_READY 0x1u

void uart_putc(char ch)
{
    // 阻塞等待最简单，适合早期裸机调试；后续需要吞吐量时再做中断/FIFO。
    while ((mmio_read(TINYBUS_UART_STATUS) & UART_STATUS_TX_READY) == 0u) {
    }

    mmio_write(TINYBUS_UART_DATA, (unsigned int)(unsigned char)ch);
}

void uart_flush(void)
{
    // 等 TX_READY 重新变高：发送中该位为低，回到高说明最后一个字节的
    // 停止位也发完了。程序退出前调用它，避免末尾字符还在串口线上就被切断。
    while ((mmio_read(TINYBUS_UART_STATUS) & UART_STATUS_TX_READY) == 0u) {
    }
}

void uart_puts(const char *str)
{
    while (*str != '\0') {
        if (*str == '\n') {
            // 很多串口终端需要 CRLF 才会回到行首。
            uart_putc('\r');
        }

        uart_putc(*str);
        str++;
    }
}

void uart_put_hex(unsigned int value)
{
    // 固定输出 "0x" + 8 位十六进制，便于对齐和肉眼比对错误码。
    static const char digits[] = "0123456789abcdef";
    int shift;

    uart_putc('0');
    uart_putc('x');

    // 从最高 nibble 到最低 nibble 逐个打印。
    for (shift = 28; shift >= 0; shift -= 4) {
        uart_putc(digits[(value >> shift) & 0xfu]);
    }
}

void uart_put_dec(unsigned int value)
{
    // 十进制没有固定宽度，先把每一位从低到高取出来倒序存，再顺序打印。
    // 32 位无符号最大 4294967295，共 10 位，缓冲区留 10 就够。
    char buf[10];
    int len = 0;

    if (value == 0u) {
        // 单独处理 0，否则下面的 do-while 之外的写法会漏打。
        uart_putc('0');
        return;
    }

    // 反复取余得到最低位数字，先存进 buf（此时是倒序的）。
    while (value != 0u) {
        buf[len] = (char)('0' + (value % 10u));
        value /= 10u;
        len++;
    }

    // 再倒着打印出来，就是正常的高位到低位顺序。
    while (len > 0) {
        len--;
        uart_putc(buf[len]);
    }
}
