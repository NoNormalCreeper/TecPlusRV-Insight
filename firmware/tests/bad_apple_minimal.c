// Bad Apple 最小 bring-up：从 bootloader 预装的 SDRAM asset 播放 tile diff 和音符。
#include "../drivers/buzzer.h"
#include "../drivers/gpio.h"
#include "../drivers/mmio.h"
#include "../drivers/uart.h"
#include "../drivers/vga.h"

#define ASSET_BASE 0x81000000u
#define ASSET_MAGIC 0x314d4142u
#define ASSET_VERSION 1u
#define SOC_CLOCK_HZ 50000000u
#define MAX_ASSET_BYTES (1024u * 1024u)

static volatile const unsigned int *const asset =
    (volatile const unsigned int *)ASSET_BASE;

static void fail(const char *message)
{
    gpio_write_led(0xfu);
    buzzer_stop();
    uart_puts("bad apple: ");
    uart_puts(message);
    uart_puts("\n");
    uart_flush();
    for (;;) {
    }
}

static void wait_frames(unsigned int count)
{
    unsigned int start = vga_frame_count();
    while (((vga_frame_count() - start) & 0xffffu) < count) {
    }
}

int main(void)
{
    unsigned int total_bytes;
    unsigned int frame_count;
    unsigned int video_offset;
    unsigned int frame_period;
    unsigned int note_count;
    unsigned int note_offset;
    unsigned int video_end_word;

    gpio_write_led(1u);
    uart_puts("bad apple: image loaded, checking asset...\n");

    if (asset[0] != ASSET_MAGIC || asset[1] != ASSET_VERSION) {
        fail("asset header mismatch");
    }
    total_bytes = asset[2];
    frame_count = asset[3];
    video_offset = asset[4];
    frame_period = asset[5];
    note_count = asset[6];
    note_offset = asset[7];
    if (total_bytes < 32u || total_bytes > MAX_ASSET_BYTES ||
        frame_count == 0u || frame_count > 1000u || frame_period == 0u ||
        (video_offset & 3u) != 0u || (note_offset & 3u) != 0u ||
        video_offset < 32u || video_offset >= note_offset || note_offset >= total_bytes ||
        note_count > 256u || note_offset + note_count * 8u > total_bytes) {
        fail("asset bounds invalid");
    }
    video_end_word = note_offset / 4u;

    while (!vga_is_ready()) {
    }
    uart_puts("bad apple: playback start\n");
    mmio_write(TINYBUS_TEST_EXIT, 1u);

    for (;;) {
        unsigned int video_word = video_offset / 4u;
        volatile const unsigned int *notes = asset + note_offset / 4u;
        unsigned int next_note = 0u;
        unsigned int frame;

        for (frame = 0u; frame < frame_count; frame++) {
            unsigned int change_count;
            unsigned int change;
            if (video_word >= video_end_word) {
                fail("video stream truncated");
            }
            change_count = asset[video_word++];
            if (change_count > VGA_TILE_WORDS ||
                change_count > (video_end_word - video_word) / 2u) {
                fail("frame diff invalid");
            }
            for (change = 0u; change < change_count; change++) {
                unsigned int word_index = asset[video_word++];
                unsigned int value = asset[video_word++];
                if (word_index >= VGA_TILE_WORDS) {
                    fail("tile index invalid");
                }
                vga_write_word(word_index, value);
            }

            while (next_note < note_count && notes[next_note * 2u] == frame) {
                unsigned int hz = notes[next_note * 2u + 1u];
                buzzer_start_hz(SOC_CLOCK_HZ, hz);
                next_note++;
            }
            gpio_write_led((frame & 0xfu) | 1u);
            if ((frame & 7u) == 0u) {
                // UART 阻塞约 1 ms；期间 VGA timing 和 buzzer PWM 仍由硬件继续运行。
                uart_putc('.');
            }
            wait_frames(frame_period);
        }
        if (video_word != video_end_word) {
            fail("video stream trailing words");
        }
        buzzer_stop();
        uart_puts(" loop\n");
    }
}
