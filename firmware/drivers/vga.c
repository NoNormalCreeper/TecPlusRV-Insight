#include "mmio.h"
#include "vga.h"

unsigned int vga_is_ready(void)
{
    return (mmio_read(TINYBUS_VGA_STATUS) >> 1) & 1u;
}

unsigned int vga_is_vblank(void)
{
    return mmio_read(TINYBUS_VGA_STATUS) & 1u;
}

unsigned int vga_frame_count(void)
{
    return mmio_read(TINYBUS_VGA_STATUS) >> 16;
}

void vga_write_word(unsigned int word_index, unsigned int value)
{
    if (word_index < VGA_TILE_WORDS) {
        mmio_write(TINYBUS_VGA_TILE_BASE + word_index * 4u, value);
    }
}

void vga_bitmap_write_word(unsigned int word_index, unsigned int value)
{
    if (word_index < VGA_BITMAP_WORDS) {
        mmio_write(TINYBUS_VGA_FB_BASE + word_index * 4u, value);
    }
}
