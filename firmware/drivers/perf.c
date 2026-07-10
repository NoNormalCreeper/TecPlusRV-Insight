// 性能计数器驱动实现。
// 计数器是顶层 tecplus_minisoc_top.v 里的 cycle_count / instret_count，
// 通过 TinyBus MMIO 暴露；这里只做读取和简单的差值/CPI 计算。
#include "perf.h"
#include "mmio.h"
#include "uart.h"

unsigned int perf_read_cycle(void)
{
    return mmio_read(TINYBUS_CYCLE);
}

unsigned int perf_read_instret(void)
{
    return mmio_read(TINYBUS_INSTRET);
}

unsigned int perf_read_mem_wait(void)
{
    return mmio_read(TINYBUS_MEM_WAIT);
}

void perf_begin(perf_snapshot_t *snap)
{
    // 先抓起点。注意读两个寄存器本身也要花几拍，属于固定测量开销，
    // 对比不同实现时开销一致可以抵消，这里不额外校正。
    snap->cycle = perf_read_cycle();
    snap->instret = perf_read_instret();
    snap->mem_wait = perf_read_mem_wait();
}

void perf_end(perf_snapshot_t *snap)
{
    // 计数器是单调递增的无符号数；即使中途回绕，无符号减法仍给出正确差值。
    unsigned int cycle_now = perf_read_cycle();
    unsigned int instret_now = perf_read_instret();
    unsigned int mem_wait_now = perf_read_mem_wait();

    snap->cycle = cycle_now - snap->cycle;
    snap->instret = instret_now - snap->instret;
    snap->mem_wait = mem_wait_now - snap->mem_wait;
}

void perf_report(const char *label, const perf_snapshot_t *snap)
{
    // CPI = cycles / instret。裸机没有浮点，用定点算到两位小数：
    // 把 cycles 乘 100 再整数除，得到的商就是 "CPI * 100"。
    unsigned int cpi_x100 = 0u;
    if (snap->instret != 0u) {
        cpi_x100 = (snap->cycle * 100u) / snap->instret;
    }

    uart_puts("[perf] ");
    uart_puts(label);
    uart_puts(": cycles=");
    uart_put_dec(snap->cycle);
    uart_puts(" instret=");
    uart_put_dec(snap->instret);
    uart_puts(" mem_wait=");
    uart_put_dec(snap->mem_wait);
    uart_puts(" CPI=");
    uart_put_dec(cpi_x100 / 100u);   // 整数部分
    uart_putc('.');
    // 小数两位：不足两位要补前导 0，比如 .05 不能打成 .5
    {
        unsigned int frac = cpi_x100 % 100u;
        if (frac < 10u) {
            uart_putc('0');
        }
        uart_put_dec(frac);
    }
    uart_putc('\n');
}
