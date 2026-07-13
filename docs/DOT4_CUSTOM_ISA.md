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

ISE 中设置 `CPU_IMPL=1`、`BOOTLOADER_ENABLE=1`、`VGA_TEXT_ENABLE=0`，并保存：

1. XST/Map 报告：无 `OVERMAPPED`，记录 Slice/LUT/FF 与 DSP48A1 数量；
2. PAR/Timing Report：50 MHz post-route slack 必须为正；
3. hierarchy：`g_darkriscv` 和 `u_dot4` 未被 trim；
4. UART 原始日志：scalar/custom checksum 相同，custom cycles/instret 更低。

本地 Icarus 不能证明 DSP 推断、板级 Fmax 或真实上板行为，因此在收到这些报告前，
文档只能声明“仿真通过”，不能声明硬件验收完成。
