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
