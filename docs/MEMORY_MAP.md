# 地址映射

## 当前草案

| 地址 | 大小 | 用途 |
| --- | --- | --- |
| `0x0000_0000 - 0x0000_1FFF` | 8 KiB | BRAM 启动区 / 小型 firmware |
| `0x1000_0000` | 32 位 | GPIO LED |
| `0x1000_0004` | 32 位 | GPIO KEY |
| `0x1000_0010` | 32 位 | UART DATA |
| `0x1000_0014` | 32 位 | UART STATUS |
| `0x1000_0020` | 32 位 | cycle counter |
| `0x1000_0024` | 32 位 | instret counter |
| `0x1000_0030` | 32-bit | test_exit |
| `0x2000_0000` | 区域基址 | accelerator base |
| `0x8000_0000` | 区域基址 | SDRAM 预留区域 |

## 说明

- 这是当前第一版骨架的软件可见地址图草案。
- 近期真正会用到的主要是 LED、KEY、UART 和 `test_exit`。
- 计数器和 accelerator 项先写入地址图，方便后续 firmware 与总线接口提前稳定。
- SDRAM 当前只做地址预留，不宣称已经实现控制器。
