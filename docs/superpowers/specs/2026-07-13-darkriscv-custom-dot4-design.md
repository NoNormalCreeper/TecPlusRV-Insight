# DarkRISCV custom-0 DOT4 设计

## 目标与边界

TecPlusRV 在 DarkRISCV profile 中实现一条非标准 `dot4.s8 rd, rs1, rs2`：两个
32-bit 源寄存器各打包四个 signed INT8，硬件完成四组乘法并求和，将 signed
32-bit 结果写回 `rd`。

第一版不修改 PicoRV32，不实现完整 SIMD/Vector ISA，不使用旧 `rd` 作为累加输入。
MMIO frontend 作为后续接口开销实验，不进入本轮实现。

## 编码与异常

```text
opcode = 0001011 (custom-0)
funct3 = 000
funct7 = 0000000
```

lane 0 固定为 `[7:0]`，lane 3 固定为 `[31:24]`。除上述编码外的 custom-0
必须触发 illegal-instruction trap；`rd=x0` 不得改变 x0。

## 硬件结构

独立 `rtl/accel/dot4_int8.v` 负责 signed 乘加。DarkRISCV 通过现有 `CPR_*`
协处理器接口连接，新增 `CPR_PC` 作为 transaction tag。结果寄存后只对相同 PC
拉高 ACK；相邻 DOT4 的 PC 改变会立即撤销旧 ACK，避免重复接收或复用旧结果。

协处理器等待沿用 core 的 `HLT`。interrupt 在 DOT4 完成后的完整指令边界进入，
性能计数器对每条合法 DOT4 只计一次提交。

## 软件与验证

`firmware/accel/dot4.S` 提供 `dot4_s8(a, b)` ABI，只有显式
`FIRMWARE_ACCEL=dot4` 才链接；其余 firmware 保持 RV32I。

验证分为：

1. signed lane、边界值、reset 和相邻 transaction 的模块级 testbench；
2. 写回、x0、非法编码、stall/retire 和 timer IRQ 的 core-level 汇编测试；
3. scalar/custom checksum、cycles、instret 的 MiniSoC benchmark；
4. 官方 RV32I/RV32MI 与现有 smoke 回归；
5. ISE Map/PAR/Timing 和真实上板人工 Gate。

Icarus 只证明 RTL 功能和相对周期结果。DSP48A1 推断、资源增量、50 MHz slack 与
板级 UART 行为必须以 ISE 和真实硬件证据为准。
