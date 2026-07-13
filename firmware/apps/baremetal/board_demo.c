// 不依赖外部 asset 的 MiniSoC 短时综合巡检。
#include "drivers/buzzer.h"
#include "drivers/gpio.h"
#include "drivers/mmio.h"
#include "drivers/perf.h"
#include "drivers/traffic_light.h"
#include "drivers/uart.h"
#include "drivers/vga.h"

#define BOARD_CLOCK_HZ 50000000u
#define TONE_HZ 1000u
#define FIRST_ROUND_DELAY 2000u
#define VISIBLE_LOOP_DELAY 400000u
#define VGA_READY_TIMEOUT 100000u

static volatile unsigned int sdram_seed[4]
    __attribute__((section(".sdram_data"))) = {
        0x13579bdfu,
        0x2468ace0u,
        0x55aa55aau,
        0xa5a5a5a5u,
    };
static volatile unsigned int sdram_scratch[8]
    __attribute__((section(".sdram_bss")));

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

static const unsigned int k_traffic_pattern[4] = {
    0x924u,
    0x492u,
    0x249u,
    0x492u,
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
        traffic_light_write(k_traffic_pattern[i]);
        uart_puts(k_step_message[i]);
        busy_delay(delay_rounds);
    }
}

static void fail(unsigned int code)
{
    buzzer_stop();
    gpio_write_led(0x0fu);
    uart_puts("board_demo FAIL code=");
    uart_put_hex(code);
    uart_puts("\n");
    uart_flush();
    mmio_write(TINYBUS_TEST_EXIT, code);
    for (;;) {
    }
}

static unsigned int check_sdram(void)
{
    static const unsigned int expected_seed[4] = {
        0x13579bdfu,
        0x2468ace0u,
        0x55aa55aau,
        0xa5a5a5a5u,
    };
    unsigned int checksum = 0u;
    unsigned int i;

    for (i = 0u; i < 4u; ++i) {
        if (sdram_seed[i] != expected_seed[i]) {
            fail(0xdead0100u + i);
        }
    }
    for (i = 0u; i < 8u; ++i) {
        if (sdram_scratch[i] != 0u) {
            fail(0xdead0200u + i);
        }
        sdram_scratch[i] = sdram_seed[i & 3u] ^ (0x01010101u * i);
    }
    for (i = 0u; i < 8u; ++i) {
        unsigned int expected = sdram_seed[i & 3u] ^ (0x01010101u * i);
        if (sdram_scratch[i] != expected) {
            fail(0xdead0300u + i);
        }
        checksum += sdram_scratch[i];
    }
    return checksum;
}

static int draw_vga_pattern(void)
{
    unsigned int wait_count = 0u;
    unsigned int y;

    while (!vga_is_ready() && wait_count < VGA_READY_TIMEOUT) {
        wait_count++;
    }
    if (!vga_is_ready()) {
        return 0;
    }

    for (y = 0u; y < VGA_BITMAP_HEIGHT; ++y) {
        unsigned int pattern = 0x80000001u;
        if (y == 0u || y == VGA_BITMAP_HEIGHT / 2u ||
            y == VGA_BITMAP_HEIGHT - 1u) {
            pattern = 0xffffffffu;
        }
        vga_bitmap_write_word(y * 2u, pattern);
        vga_bitmap_write_word(y * 2u + 1u, pattern);
    }
    return 1;
}

int main(void)
{
    perf_snapshot_t perf;
    unsigned int checksum;
    unsigned int key;
    int vga_ready;

    uart_puts("board_demo boot\n");
    perf_begin(&perf);

    checksum = check_sdram();
    uart_puts("board_demo SDRAM PASS checksum=");
    uart_put_hex(checksum);
    uart_puts("\n");

    vga_ready = draw_vga_pattern();
    uart_puts(vga_ready ? "board_demo VGA PASS\n" : "board_demo VGA SKIP\n");

    buzzer_start_hz(BOARD_CLOCK_HZ, TONE_HZ);
    play_visible_round(FIRST_ROUND_DELAY);
    buzzer_stop();

    key = gpio_read_key() & 0x0fu;
    uart_puts("board_demo KEY=0x");
    uart_put_hex(key);
    uart_puts("\n");

    perf_end(&perf);
    perf_report("board_demo", &perf);
    uart_puts("board_demo PASS\n");
    uart_flush();

    traffic_light_write(0x249u);
    gpio_write_led(0x5u);
    mmio_write(TINYBUS_TEST_EXIT, 1u);
    busy_delay(VISIBLE_LOOP_DELAY);

    for (;;) {
        buzzer_start_hz(BOARD_CLOCK_HZ, TONE_HZ);
        play_visible_round(VISIBLE_LOOP_DELAY);
        buzzer_stop();
        busy_delay(VISIBLE_LOOP_DELAY);
    }
}
