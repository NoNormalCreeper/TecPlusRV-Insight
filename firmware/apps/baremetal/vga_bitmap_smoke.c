// 64x48 1bpp VGA MMIO 静态图样上板验收程序。
#include "drivers/vga.h"
#include "tests/testlib.h"

#define READY_TIMEOUT 1000000u

int main(void)
{
    unsigned int wait_count = 0u;
    unsigned int y;
    unsigned int left;
    unsigned int right;
    unsigned int start_frame;

    test_banner("vga bitmap smoke");

    while (!vga_is_ready()) {
        wait_count++;
        if (wait_count >= READY_TIMEOUT) {
            uart_puts("vga bitmap fail: not ready\n");
            test_fail(0xdead0501u);
        }
    }

    // 边框加中心十字，方便确认方向、缩放和完整 64x48 有效区域。
    for (y = 0u; y < VGA_BITMAP_HEIGHT; y++) {
        if (y == 0u || y == VGA_BITMAP_HEIGHT - 1u ||
            y == VGA_BITMAP_HEIGHT / 2u) {
            left = 0xffffffffu;
            right = 0xffffffffu;
        } else {
            left = 0x80000001u;
            right = 0x80000001u;
        }
        vga_bitmap_write_word(y * 2u, left);
        vga_bitmap_write_word(y * 2u + 1u, right);
    }

    start_frame = vga_frame_count();
    while (vga_frame_count() == start_frame) {
    }

    uart_puts("vga bitmap smoke pass\n");
    test_pass();
    return 0;
}
