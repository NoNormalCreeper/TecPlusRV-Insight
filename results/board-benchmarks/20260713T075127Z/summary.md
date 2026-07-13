# 板级性能实验汇总

- 运行编号：`20260713T075127Z`
- 环境：`environment.txt`
- 原始串口日志：`*_board.log`
- 口径：cycle / instret / mem_wait 来自真实板子的 firmware 计数器输出。

| benchmark | scope | cycles | instret | mem_wait | CPI |
| --- | --- | ---: | ---: | ---: | ---: |
| perf_mix | alu_dep | 65604 | 24595 | 20 | 2.667 |
| perf_mix | branch_alternating | 86086 | 26644 | 20 | 3.231 |
| perf_mix | bram_load_store | 32832 | 10257 | 8212 | 3.201 |
| perf_mix | mixed | 100748 | 35959 | 16404 | 2.802 |
| system_bench | stencil_bram | 54966 | 17308 | 16276 | 3.176 |
| system_bench | stencil_sdram | 125908 | 17308 | 91079 | 7.275 |
| riscv_tests_median | bram | 23350 | 5610 | 6396 | 4.162 |
| riscv_tests_median | sdram | 51312 | 5609 | 35881 | 9.148 |
| riscv_tests_memcpy | bram_to_bram | 128126 | 32036 | 32020 | 3.999 |
| riscv_tests_memcpy | sdram_to_sdram | 261822 | 32034 | 173435 | 8.173 |
