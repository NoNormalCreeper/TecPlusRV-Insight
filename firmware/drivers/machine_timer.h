// CLINT-like machine timer 的 RV32 firmware 接口。
#ifndef MACHINE_TIMER_H
#define MACHINE_TIMER_H

#define MACHINE_TIMER_INTERRUPT_CAUSE 0x80000007u
#define MACHINE_TIMER_MIE_MASK (1u << 7)

unsigned long long machine_timer_now(void);
void machine_timer_set_compare(unsigned long long value);

#endif
