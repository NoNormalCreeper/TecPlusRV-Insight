// DarkRISCV SDRAM 连续重叠读回归。
//
// median 的滑动窗口会在相邻迭代中再次读取刚访问过的地址；曾经的
// ``same_as_last_req`` 重放优化把它误判为旧请求，最终让总线卡死。
// 这个最小程序固定产生 a[0], a[1], a[2], a[1] 的重叠读序列，便于
// 在不运行完整 benchmark 的情况下验证该类访问。
#include "testlib.h"

int main(void)
{
    volatile unsigned int *const a =
        (volatile unsigned int *)(TINYBUS_SDRAM_BASE + 0x100u);
    unsigned int sum = 0u;
    unsigned int i;

    test_banner("sdram_overlap_read");

    a[0] = 0x10203040u;
    a[1] = 0x50607080u;
    a[2] = 0x90a0b0c0u;

    for (i = 0u; i < 32u; i++) {
        sum += a[0];
        sum += a[1];
        sum += a[2];
        sum += a[1];
    }

    test_expect(sum == 0x30384000u, 0xdead5101u);
    test_pass();
    return 0;
}
