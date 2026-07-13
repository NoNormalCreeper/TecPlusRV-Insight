// 板上最小可见 demo。
// 首轮依次切换 4 个 LED 图样并打印 UART 文本，随后写一次 test_exit=1 方便仿真收敛；
// 之后继续无限循环，同一份程序也适合直接导入 ISE 上板观察。
#include "drivers/gpio.h"
#include "drivers/mmio.h"
#include "drivers/uart.h"

static const unsigned int k_led_pattern[4] = {
    0x1u,
    0x2u,
    0x4u,
    0x8u,
};

static const char *const k_step_message[4] = {
    "step 0 led=0x1\n",
    "step 1 led=0x2\n",
    "step 2 led=0x4\n",
    "step 3 led=0x8\n",
};

static void busy_delay(unsigned int rounds)
{
    volatile unsigned int i;

    for (i = 0; i < rounds; ++i) {
        __asm__ volatile ("" ::: "memory");
    }
}

static void play_visible_round(unsigned int delay_rounds)
{
    unsigned int i;

    for (i = 0; i < 4u; ++i) {
        gpio_write_led(k_led_pattern[i]);
        uart_puts(k_step_message[i]);
        busy_delay(delay_rounds);
    }
}

int main(void)
{
    int first_round = 1;
    unsigned int delay_rounds = 2000u;

    uart_puts("board_demo boot\n");

    for (;;) {
        play_visible_round(delay_rounds);

        if (first_round != 0) {
            uart_puts("board_demo first round done\n");
            mmio_write(TINYBUS_TEST_EXIT, 1u);
            first_round = 0;
            delay_rounds = 400000u;
        }
    }

    return 0;
}
