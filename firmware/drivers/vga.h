// packed tile VGA 的最小 firmware 接口。
#ifndef VGA_H
#define VGA_H

#define VGA_TILE_WORDS 300u
#define VGA_BITMAP_WIDTH 64u
#define VGA_BITMAP_HEIGHT 48u
#define VGA_BITMAP_WORDS 96u

unsigned int vga_is_ready(void);
unsigned int vga_is_vblank(void);
unsigned int vga_frame_count(void);
void vga_write_word(unsigned int word_index, unsigned int value);
void vga_bitmap_write_word(unsigned int word_index, unsigned int value);

#endif
