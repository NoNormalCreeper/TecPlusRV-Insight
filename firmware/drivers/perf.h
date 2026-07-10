// 性能计数器驱动接口。
// 顶层架构里有两个硬件计数器：cycle（每个时钟周期 +1）和 instret（每退休一条
// 指令 +1）。这个驱动负责读它们，并提供"测一段代码花了多少周期"的辅助功能，
// 是后续 benchmark / PPA 分析（cycles / CPI / speedup）的软件地基。
#ifndef PERF_H
#define PERF_H

// 直接读两个硬件计数器的当前值。
unsigned int perf_read_cycle(void);
unsigned int perf_read_instret(void);
unsigned int perf_read_mem_wait(void);

// 一次性抓取的性能快照，配合下面的 begin/end 使用。
typedef struct {
    unsigned int cycle;
    unsigned int instret;
    unsigned int mem_wait;
} perf_snapshot_t;

// 记录当前 cycle / instret，作为一段测量的起点。
void perf_begin(perf_snapshot_t *snap);

// 用起点快照算出这段代码经过的周期数和指令数（结果写回同一个 snap）。
// 调用后 snap->cycle / snap->instret 变成"差值"，即这段代码实际消耗量。
void perf_end(perf_snapshot_t *snap);

// 把一段测量结果按 "cycles=.. instret=.. CPI=.." 格式打印到 UART。
// CPI 用定点方式打印（整数部分.两位小数），裸机没有浮点也能给出可读结果。
void perf_report(const char *label, const perf_snapshot_t *snap);

#endif
