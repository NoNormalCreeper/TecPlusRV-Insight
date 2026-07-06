#include "mmio.h"
#include "uart.h"

#define UART_STATUS_TX_READY 0x1u

void uart_putc(char ch)
{
    while ((mmio_read(TINYBUS_UART_STATUS) & UART_STATUS_TX_READY) == 0u) {
    }

    mmio_write(TINYBUS_UART_DATA, (unsigned int)(unsigned char)ch);
}

void uart_puts(const char *str)
{
    while (*str != '\0') {
        if (*str == '\n') {
            uart_putc('\r');
        }

        uart_putc(*str);
        str++;
    }
}

