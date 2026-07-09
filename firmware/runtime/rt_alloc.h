// 最小 bump allocator。
// 只维护一个游标，分配即向前推进；不支持单块 free（reset 靠 heap_init 整体重来）。
// 裸机早期够用：把 SDRAM（M3 阶段暂为 BRAM）里的 heap 区当线性池切。
#ifndef RT_ALLOC_H
#define RT_ALLOC_H

#include <stddef.h>

// 初始化 / 重置 heap 游标到起点。可重复调用（reset 后重新初始化）。
void heap_init(void);

// 从 heap 分配 size 字节，起始地址按 align 对齐（align 需为 2 的幂）。
// 成功返回对齐后的指针；空间不足返回 NULL。align 传 0 时按默认 4 字节对齐。
void *bump_alloc(size_t size, size_t align);

// 当前已用字节数（游标相对 heap 起点的偏移），用于测试/观察。
size_t heap_used(void);

#endif
