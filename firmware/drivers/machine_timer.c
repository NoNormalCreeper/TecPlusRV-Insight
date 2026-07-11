// RV32 上安全读取 mtime，并按推荐顺序更新 mtimecmp。
#include "machine_timer.h"
#include "mmio.h"

unsigned long long machine_timer_now(void)
{
    unsigned int hi0;
    unsigned int lo;
    unsigned int hi1;

    do {
        hi0 = mmio_read(TINYBUS_MTIME_HI);
        lo = mmio_read(TINYBUS_MTIME_LO);
        hi1 = mmio_read(TINYBUS_MTIME_HI);
    } while (hi0 != hi1);

    return ((unsigned long long)hi1 << 32) | lo;
}

void machine_timer_set_compare(unsigned long long value)
{
    // 先把 low 临时抬到最大值，避免分两次写 64-bit compare 时意外触发。
    mmio_write(TINYBUS_MTIMECMP_LO, 0xffffffffu);
    mmio_write(TINYBUS_MTIMECMP_HI, (unsigned int)(value >> 32));
    mmio_write(TINYBUS_MTIMECMP_LO, (unsigned int)value);
}
