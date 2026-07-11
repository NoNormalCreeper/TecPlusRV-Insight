// 本工具链没有 libc headers；FreeRTOS 静态配置只需要这些基础定义。
#ifndef FREERTOS_COMPAT_STDLIB_H
#define FREERTOS_COMPAT_STDLIB_H

#include <stddef.h>
#include <stdint.h>

#ifndef NULL
#define NULL ((void *)0)
#endif

#ifndef SIZE_MAX
#define SIZE_MAX UINTPTR_MAX
#endif

#endif
