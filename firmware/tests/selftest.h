// SoC 自检测试的统一入口。
// firmware 启动后调用 selftest_run_all()，让 CPU 主动去"考"硬件：
// 指令执行是否正确、BRAM 读写是否可靠、MMIO 外设是否可访问。
//
// 返回值约定（和 test_exit / testbench 对齐）：
//   0x00000001            全部通过（PASS）
//   0xdeadXXXX            某项失败（FAIL），低 16 位是错误码，指明失败位置
//
// 错误码分段（高字节=测试类别，低字节=子项）：
//   0xdead01xx  ISA 指令测试
//   0xdead02xx  BRAM 存储测试
//   0xdead03xx  MMIO 外设测试
#ifndef SELFTEST_H
#define SELFTEST_H

#define SELFTEST_PASS 0x00000001u

unsigned int selftest_run_all(void);

#endif
