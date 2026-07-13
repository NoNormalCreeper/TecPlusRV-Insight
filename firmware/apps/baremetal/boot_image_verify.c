// LOAD_IMAGE 上板 verifier：CPU 释放后从 SDRAM 全量读回确定性 BTV1 asset。
#include "tests/testlib.h"

#define ASSET_BASE 0x81000000u
#define ASSET_MAGIC 0x31565442u
#define ASSET_VERSION 1u
#define HEADER_WORDS 4u
#define MAX_DATA_WORDS (1024u * 1024u / 4u)
#define PATTERN_MULTIPLIER 0x9e3779b9u

static volatile const unsigned int *const asset =
    (volatile const unsigned int *)ASSET_BASE;

static unsigned int pattern_word(unsigned int index, unsigned int seed)
{
    return seed ^ (index * PATTERN_MULTIPLIER);
}

static void fail(unsigned int code, unsigned int index,
                 unsigned int expected, unsigned int actual)
{
    uart_puts("boot_image_verify: FAIL code=");
    uart_put_hex(code);
    uart_puts(" index=");
    uart_put_dec(index);
    uart_puts(" expected=");
    uart_put_hex(expected);
    uart_puts(" actual=");
    uart_put_hex(actual);
    uart_puts("\n");
    uart_flush();
    gpio_write_led(0xfu);
    mmio_write(TINYBUS_TEST_EXIT, code);
    for (;;) {
    }
}

int main(void)
{
    unsigned int data_words;
    unsigned int seed;
    unsigned int start_cycles;
    unsigned int index;

    gpio_write_led(1u);
    uart_puts("boot_image_verify: checking SDRAM asset at 0x81000000\n");

    if (asset[0] != ASSET_MAGIC) {
        fail(0xb1000001u, 0u, ASSET_MAGIC, asset[0]);
    }
    if (asset[1] != ASSET_VERSION) {
        fail(0xb1000002u, 1u, ASSET_VERSION, asset[1]);
    }

    data_words = asset[2];
    seed = asset[3];
    if (data_words == 0u || data_words > MAX_DATA_WORDS) {
        fail(0xb1000003u, 2u, MAX_DATA_WORDS, data_words);
    }

    gpio_write_led(2u);
    start_cycles = test_read_cycle();
    for (index = 0u; index < data_words; index++) {
        unsigned int expected = pattern_word(index, seed);
        unsigned int actual = asset[HEADER_WORDS + index];
        if (actual != expected) {
            fail(0xb1000010u, index, expected, actual);
        }
    }

    uart_puts("boot_image_verify: PASS bytes=");
    uart_put_dec(data_words * 4u);
    uart_puts(" seed=");
    uart_put_hex(seed);
    uart_puts(" verify_cycles=");
    uart_put_dec(test_read_cycle() - start_cycles);
    uart_puts("\n");
    uart_flush();
    test_pass();
    return 0;
}
