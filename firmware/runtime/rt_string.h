// 裸机最小内存操作库。
// 只覆盖 rv32i freestanding 场景真正会用到的子集，不追求完整 C 标准库兼容面。
// 语义与标准 C 一致：返回目的指针；size 以字节计。
#ifndef RT_STRING_H
#define RT_STRING_H

#include <stddef.h>

// 把 src 起 n 字节拷到 dest。要求源和目的不重叠（重叠请用 rt_memmove）。
void *rt_memcpy(void *dest, const void *src, size_t n);
void *memcpy(void *dest, const void *src, size_t n);

// 把 dest 起 n 字节全部设为 (unsigned char)value。
void *rt_memset(void *dest, int value, size_t n);
void *memset(void *dest, int value, size_t n);

// 与 rt_memcpy 相同，但正确处理源和目的重叠的情况。
void *rt_memmove(void *dest, const void *src, size_t n);
void *memmove(void *dest, const void *src, size_t n);

#endif
