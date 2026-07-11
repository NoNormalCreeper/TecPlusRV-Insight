// FreeRTOS kernel 使用的最小 string.h 声明；实现由现有 runtime 提供。
#ifndef FREERTOS_COMPAT_STRING_H
#define FREERTOS_COMPAT_STRING_H

#include <stddef.h>

void *memcpy(void *dest, const void *src, size_t count);
void *memmove(void *dest, const void *src, size_t count);
void *memset(void *dest, int value, size_t count);
size_t strlen(const char *str);
char *strcpy(char *dest, const char *src);

#endif
