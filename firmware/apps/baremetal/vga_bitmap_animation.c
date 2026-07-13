// 64x48 1bpp VGA MMIO 动态写入 demo。
#include "drivers/gpio.h"
#include "drivers/uart.h"
#include "drivers/vga.h"

static void draw_checker(unsigned int phase)
{
    unsigned int y;
    unsigned int pattern;

    for (y = 0u; y < VGA_BITMAP_HEIGHT; y++) {
        pattern = ((y + phase) & 1u) ? 0xaaaaaaaau : 0x55555555u;
        vga_bitmap_write_word(y * 2u, pattern);
        vga_bitmap_write_word(y * 2u + 1u, pattern);
    }
}

int main(void)
{
    unsigned int frame;
    unsigned int phase = 0u;

    uart_puts("vga bitmap animation start\n");
    while (!vga_is_ready()) {
    }

    frame = vga_frame_count();
    for (;;) {
        if (vga_frame_count() != frame) {
            frame = vga_frame_count();
            // 每 16 帧翻转一次，肉眼可见且不会持续占满 MMIO。
            if ((frame & 15u) == 0u) {
                phase ^= 1u;
                draw_checker(phase);
                gpio_write_led(phase ? 0xau : 0x5u);
            }
        }
    }
}
