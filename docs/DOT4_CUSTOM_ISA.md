# DarkRISCV custom-0 DOT4 扩展

## 指令语义

`dot4.s8 rd, rs1, rs2` 使用 RISC-V `custom-0` opcode，只在 TecPlusRV 的
DarkRISCV profile 中实现：

```text
opcode = 0001011
funct3 = 000
funct7 = 0000000

rd = signed(rs1[7:0])   * signed(rs2[7:0])
   + signed(rs1[15:8])  * signed(rs2[15:8])
   + signed(rs1[23:16]) * signed(rs2[23:16])
   + signed(rs1[31:24]) * signed(rs2[31:24])
```

结果写回 signed 32-bit。它是一条 packed INT8、SIMD-style dot-product 指令，
不是完整 RISC-V Vector/SIMD 扩展，也不是带旧 `rd` 输入的 MAC。其他
`custom-0` 编码必须触发 illegal-instruction trap。

## 硬件路径

```text
DarkRISCV decode/execute
  -> CPR_REQ + CPR_PC + rs1/rs2
  -> rtl/accel/dot4_int8.v
  -> CPR_ACK + result
  -> register file rd
```

`CPR_PC` 是 transaction tag。协处理器将注册结果与发起指令 PC 绑定：流水线因
`CPR_ACK` 继续后，如果下一条仍是 DOT4，PC 改变会立即撤销旧 ACK，从而避免同一条
重复执行或相邻指令错误复用旧结果。等待期间 interrupt 延后到完整指令边界。

软件 ABI 位于 `firmware/accel/dot4.S`：

```c
int dot4_s8(unsigned int packed_a, unsigned int packed_b);
```

默认 firmware 不包含该非标准指令；只有显式设置 `FIRMWARE_ACCEL=dot4` 才链接包装函数。

## 自动验证

```bash
./sim/run_sim.sh dot4_int8
./sim/run_sim.sh darkriscv_dot4
make dot4-bench
python3 scripts/test_runner.py run-suite rv32i_safe --keep-going
python3 scripts/test_runner.py run-suite rv32mi_dark --keep-going
```

覆盖范围包括 signed lane 边界、相邻请求、reset、结果写回、`rd=x0`、illegal
custom-0、协处理器 stall 中的 timer IRQ，以及 scalar/custom checksum 和性能方向。

## ISE 与上板人工 Gate

```bash
make ise-export ISE_TARGET=minisoc_dot4_dark
make dot4-load PORT=COM8
```

阶段性人工记录见 [`reports/dot4-board-validation.md`](../reports/dot4-board-validation.md)。
该报告已经记录 Map 资源、真实开发板 UART benchmark、50 MHz timing 和
`OVERMAPPED` 搜索结果；XST report 已出现 `Unit <u_dot4>`，`g_darkriscv`
层级名未直接检索到，当前以 `CPU_IMPL=1`、DSP48A1 使用量与 UART PASS
作为间接证据。

本分支的面积基线是共同祖先 `35968e6` 上的 `minisoc_dark`，不是当前分支的
`minisoc_dark`：当前分支已经全局接入 DOT4，拿它作对照会把加速器也综合进去。本地已
准备两份脱离源码树仍可独立 elaboration 的导出包：

```text
build/ise-export/minisoc_dark_baseline-35968e6
build/ise-export/minisoc_dot4_dark-final
```

两份工程都设置相同的 `CPU_IMPL=1`、`BOOTLOADER_ENABLE=1`、
`VGA_TEXT_ENABLE=0`，使用同一器件、ISE 设置和 50 MHz 约束。报告至少并排记录：

| 配置 | Slice | LUT | FF | RAMB16 | DSP48A1 | 50 MHz slack |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| DarkRISCV baseline (`35968e6`) | 待填写 | 待填写 | 待填写 | 待填写 | 待填写 | 待填写 |
| DarkRISCV + DOT4（报告中记录实际 feature HEAD） | 待填写 | 待填写 | 待填写 | 待填写 | 待填写 | 待填写 |
| 增量 | 待计算 | 待计算 | 待计算 | 待计算 | 待计算 | — |

DSP48A1 数量用于解释实现方式，不作为功能正确性的硬性条件：XST 可能把四个 signed
8x8 乘法映射到 DSP，也可能使用 LUT。无论采用哪种映射，都必须确认 `u_dot4` 未被
trim、Map 未 overmap 且 post-route slack 为正。

ISE 中设置 `CPU_IMPL=1`、`BOOTLOADER_ENABLE=1`、`VGA_TEXT_ENABLE=0`，并保存：

1. XST/Map 报告：无 `OVERMAPPED`，记录 Slice/LUT/FF 与 DSP48A1 数量；
2. PAR/Timing Report：50 MHz post-route slack 必须为正；
3. hierarchy：`g_darkriscv` 和 `u_dot4` 未被 trim；
4. UART 原始日志：scalar/custom checksum 相同，custom cycles/instret 更低。

本地 Icarus 不能证明 DSP 推断、板级 Fmax 或真实上板行为，因此在收到这些报告前，
文档只能声明“仿真通过”，不能声明硬件验收完成。
