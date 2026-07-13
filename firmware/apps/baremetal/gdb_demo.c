// GDB 交互演示：在两次 cooperative stop 之间修改输入并观察计算结果。
#include "drivers/gpio.h"
#include "runtime/debug.h"

struct gdb_demo_state {
    unsigned int phase;
    unsigned int input;
    unsigned int output;
};

volatile struct gdb_demo_state gdb_demo_state;

int main(void)
{
    gdb_demo_state.phase = 1u;
    gdb_demo_state.input = 7u;
    gdb_demo_state.output = 0u;
    gpio_write_led(1u);
    DEBUG_BREAK();

    gdb_demo_state.output = gdb_demo_state.input * 3u;
    gdb_demo_state.phase = 2u;
    gpio_write_led(2u);
    DEBUG_BREAK();

    gdb_demo_state.phase = 3u;
    gpio_write_led(5u);
    for (;;) {
    }
}
