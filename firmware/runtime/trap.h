// machine trap runtime 的最小公共接口。
#ifndef TRAP_H
#define TRAP_H

#include "trap_frame.h"

void trap_entry(void);
void trap_restore_frame(struct trap_frame *frame) __attribute__((noreturn));
void trap_init(void);
void trap_enable_machine_timer(void);

#endif
