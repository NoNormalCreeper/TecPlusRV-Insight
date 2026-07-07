#include "testlib.h"

int main(void)
{
    test_banner("smoke");
    gpio_write_led(0x5u);
    uart_puts("TecPlusRV firmware skeleton\n");
    test_pass();
    return 0;
}
