// GDB 交互演示：观察并修改 BRAM/SDRAM 状态，再从 LED 看到继续执行的结果。
#include "drivers/gpio.h"
#include "drivers/mmio.h"
#include "runtime/debug.h"

struct gdb_demo_state {
    unsigned int phase;
    unsigned int input;
    unsigned int multiplier;
    unsigned int output;
    unsigned int checksum;
};

volatile struct gdb_demo_state gdb_demo_state;
volatile unsigned int gdb_demo_sdram[4]
    __attribute__((section(".sdram_data"))) = {
        0x10u,
        0x20u,
        0x30u,
        0x40u,
    };

static unsigned int sdram_checksum(void)
{
    unsigned int i;
    unsigned int checksum = 0u;

    for (i = 0u; i < 4u; ++i) {
        checksum += gdb_demo_sdram[i];
    }
    return checksum;
}

int main(void)
{
    gdb_demo_state.phase = 1u;
    gdb_demo_state.input = 7u;
    gdb_demo_state.multiplier = 3u;
    gdb_demo_state.output = 0u;
    gdb_demo_state.checksum = 0u;
    gpio_write_led(1u);
    DEBUG_BREAK();

    gdb_demo_state.output = gdb_demo_state.input * gdb_demo_state.multiplier;
    gdb_demo_state.checksum = sdram_checksum();
    gdb_demo_state.phase = 2u;
    gpio_write_led(2u);
    DEBUG_BREAK();

    gdb_demo_state.phase = 3u;
    gpio_write_led(gdb_demo_state.output & 0x0fu);
    mmio_write(TINYBUS_TEST_EXIT, 1u);
    for (;;) {
        DEBUG_BREAK();  // endless loop
    }
}
