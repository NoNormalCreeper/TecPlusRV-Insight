# 板级性能实验汇总

- 运行编号：`20260713T082725Z`
- 环境：`environment.txt`
- 原始串口日志：`*_board.log`
- 口径：cycle / instret / mem_wait 来自真实板子的 firmware 计数器输出。

| benchmark | scope | cycles | instret | mem_wait | CPI |
| --- | --- | ---: | ---: | ---: | ---: |
| memset_bench | bram | 22654 | 5158 | 4116 | 4.392 |
| memset_bench | sdram | 37230 | 5158 | 19716 | 7.218 |
| stride_bench | stride1_bram | 90176 | 32785 | 16404 | 2.751 |
| stride_bench | stride1_sdram | 155722 | 32785 | 86045 | 4.750 |
| stride_bench | stride2_bram | 90176 | 32785 | 16404 | 2.751 |
| stride_bench | stride2_sdram | 155712 | 32785 | 86036 | 4.749 |
| stride_bench | stride4_bram | 90176 | 32785 | 16404 | 2.751 |
| stride_bench | stride4_sdram | 155712 | 32785 | 86036 | 4.749 |
| stride_bench | stride8_bram | 90176 | 32785 | 16404 | 2.751 |
| stride_bench | stride8_sdram | 155712 | 32785 | 86036 | 4.749 |
| stride_bench | stride16_bram | 90176 | 32785 | 16404 | 2.751 |
| stride_bench | stride16_sdram | 155712 | 32785 | 86036 | 4.749 |
| crc32_bench | bram | 655428 | 253971 | 16404 | 2.581 |
| crc32_bench | sdram | 729638 | 253971 | 94710 | 2.873 |
