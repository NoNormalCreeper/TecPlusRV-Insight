# 性能实验汇总

- 运行编号：`issue19-final`
- 环境：`environment.txt`
- 口径：cycle / instret / mem_wait 都是 firmware `perf_begin/perf_end` 区间差值；CPI = cycles / instret；吞吐量按 testbench 的 1 MHz 时钟换算。

| CPU | benchmark | scope | cycles | instret | mem_wait | wait % | CPI | KIPS @ 1 MHz |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| picorv32 | perf_mix | alu_dep | 151655 | 24592 | 10 | 0.0 | 6.167 | 162.2 |
| picorv32 | perf_mix | branch_alternating | 157804 | 26641 | 10 | 0.0 | 5.923 | 168.8 |
| picorv32 | perf_mix | bram_load_store | 64610 | 10255 | 4106 | 6.4 | 6.300 | 158.7 |
| picorv32 | perf_mix | mixed | 214747 | 35956 | 8202 | 3.8 | 5.972 | 167.4 |
| darkriscv | perf_mix | alu_dep | 65596 | 24592 | 20 | 0.0 | 2.667 | 374.9 |
| darkriscv | perf_mix | branch_alternating | 86078 | 26641 | 20 | 0.0 | 3.231 | 309.5 |
| darkriscv | perf_mix | bram_load_store | 32826 | 10255 | 8212 | 25.0 | 3.201 | 312.4 |
| darkriscv | perf_mix | mixed | 100740 | 35956 | 16404 | 16.3 | 2.802 | 356.9 |
| picorv32 | system_bench | stencil_bram | 115072 | 18333 | 8138 | 7.1 | 6.277 | 159.3 |
| picorv32 | system_bench | stencil_sdram | 197145 | 18333 | 90211 | 45.8 | 10.754 | 93.0 |
| darkriscv | system_bench | stencil_bram | 57046 | 18333 | 16276 | 28.5 | 3.112 | 321.4 |
| darkriscv | system_bench | stencil_sdram | 128186 | 18333 | 91278 | 71.2 | 6.992 | 143.0 |
| picorv32 | riscv_tests_median | bram | 34853 | 4942 | 3198 | 9.2 | 7.052 | 141.8 |
| picorv32 | riscv_tests_median | sdram | 67072 | 4941 | 35422 | 52.8 | 13.575 | 73.7 |
| darkriscv | riscv_tests_median | bram | 22672 | 4942 | 6396 | 28.2 | 4.588 | 218.0 |
| darkriscv | riscv_tests_median | sdram | 50616 | 4941 | 35864 | 70.9 | 10.244 | 97.6 |
| picorv32 | riscv_tests_memcpy | bram_to_bram | 208185 | 32031 | 16010 | 7.7 | 6.499 | 153.9 |
| picorv32 | riscv_tests_memcpy | sdram_to_sdram | 363370 | 32028 | 171210 | 47.1 | 11.345 | 88.1 |
| darkriscv | riscv_tests_memcpy | bram_to_bram | 128106 | 32031 | 32020 | 25.0 | 3.999 | 250.0 |
| darkriscv | riscv_tests_memcpy | sdram_to_sdram | 261812 | 32028 | 173446 | 66.2 | 8.174 | 122.3 |

原始 UART 日志与每个 workload 的构建日志均在当前目录。
