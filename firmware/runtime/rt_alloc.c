// bump allocator 实现。
// heap 区间由 linker.ld 的 _heap_start / _heap_end 界定（M3 阶段落在 BRAM）。
#include "rt_alloc.h"

// linker.ld 导出的 heap 边界符号。取地址得到区间端点。
extern unsigned char _heap_start[];
extern unsigned char _heap_end[];

// 默认对齐：rv32i 字访问友好。
#define RT_ALLOC_DEFAULT_ALIGN 4u

// 分配游标，始终指向下一次分配的候选起点。
static unsigned char *g_heap_cursor;

void heap_init(void)
{
    g_heap_cursor = _heap_start;
}

void *bump_alloc(size_t size, size_t align)
{
    unsigned char *base;
    unsigned char *next;
    size_t mask;
    size_t misalign;

    // 未初始化时懒初始化，避免忘调 heap_init 直接踩空指针。
    if (g_heap_cursor == 0) {
        g_heap_cursor = _heap_start;
    }

    if (align == 0u) {
        align = RT_ALLOC_DEFAULT_ALIGN;
    }

    // 把游标向上对齐到 align 边界。align 是 2 的幂，用掩码算余数。
    mask = align - 1u;
    misalign = (size_t)((unsigned long)g_heap_cursor & mask);
    base = g_heap_cursor;
    if (misalign != 0u) {
        base += (align - misalign);
    }

    // 越界检查放在推进游标之前，避免溢出后污染 g_heap_cursor。
    // 用端点相减得到剩余容量，避免 base+size 的指针算术溢出风险。
    if (base > _heap_end) {
        return 0;
    }
    if (size > (size_t)(_heap_end - base)) {
        return 0;
    }

    next = base + size;
    g_heap_cursor = next;
    return base;
}

size_t heap_used(void)
{
    if (g_heap_cursor == 0) {
        return 0u;
    }
    return (size_t)(g_heap_cursor - _heap_start);
}
