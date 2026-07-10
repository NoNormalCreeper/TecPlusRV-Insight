// 裸机最小内存操作库实现。
// 逐字节实现，简单可靠；rv32i 无对齐访问优化需求时这样最稳。
#include "rt_string.h"

void *rt_memcpy(void *dest, const void *src, size_t n)
{
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)src;
    // SDRAM 控制器以 32-bit 请求服务 CPU。对齐的大块 copy 若仍逐字节访问，
    // 会把一条 word copy 放大成四笔总线事务；先处理 byte tail，再走 word fast path。
    while (n != 0u && (((unsigned long)d | (unsigned long)s) & 3u) != 0u) {
        *d++ = *s++;
        n--;
    }
    while (n >= 4u) {
        *(unsigned int *)d = *(const unsigned int *)s;
        d += 4;
        s += 4;
        n -= 4u;
    }
    while (n != 0u) {
        *d++ = *s++;
        n--;
    }

    return dest;
}

void *rt_memset(void *dest, int value, size_t n)
{
    unsigned char *d = (unsigned char *)dest;
    unsigned char v = (unsigned char)value;
    unsigned int word = (unsigned int)v;

    word |= word << 8;
    word |= word << 16;
    while (n != 0u && ((unsigned long)d & 3u) != 0u) {
        *d++ = v;
        n--;
    }
    while (n >= 4u) {
        *(unsigned int *)d = word;
        d += 4;
        n -= 4u;
    }
    while (n != 0u) {
        *d++ = v;
        n--;
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

void *memcpy(void *dest, const void *src, size_t n)
{
    return rt_memcpy(dest, src, n);
}

void *memset(void *dest, int value, size_t n)
{
    return rt_memset(dest, value, n);
}

void *memmove(void *dest, const void *src, size_t n)
{
    return rt_memmove(dest, src, n);
}
