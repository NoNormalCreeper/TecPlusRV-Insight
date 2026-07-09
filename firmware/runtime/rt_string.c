// 裸机最小内存操作库实现。
// 逐字节实现，简单可靠；rv32i 无对齐访问优化需求时这样最稳。
#include "rt_string.h"

void *rt_memcpy(void *dest, const void *src, size_t n)
{
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)src;
    size_t i;

    for (i = 0u; i < n; i++) {
        d[i] = s[i];
    }

    return dest;
}

void *rt_memset(void *dest, int value, size_t n)
{
    unsigned char *d = (unsigned char *)dest;
    unsigned char v = (unsigned char)value;
    size_t i;

    for (i = 0u; i < n; i++) {
        d[i] = v;
    }

    return dest;
}

void *rt_memmove(void *dest, const void *src, size_t n)
{
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)src;
    size_t i;

    if (d == s || n == 0u) {
        return dest;
    }

    // 重叠处理：目的在源之后（d>s）时从高地址往低地址拷，
    // 否则先被覆盖的字节会污染还没读的源数据；反向则相反。
    if (d < s) {
        for (i = 0u; i < n; i++) {
            d[i] = s[i];
        }
    } else {
        for (i = n; i > 0u; i--) {
            d[i - 1u] = s[i - 1u];
        }
    }

    return dest;
}
