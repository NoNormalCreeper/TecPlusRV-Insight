`ifndef DARKRISCV_CONFIG_VH
`define DARKRISCV_CONFIG_VH

// 当前 MiniSoC 只启用最小配置：3-stage RV32I、reset PC 从 0 开始，
// 并打开基础 CSR 计数器，方便后续做性能对照。
`define __3STAGE__
`define __CSR__
`define __CSR_ESSENTIAL__
// 启用 TecPlusRV custom-0 DOT4 协处理器握手。
`define __COPROCESSOR__
// TecPlusRV 只实现 M-mode-only 的 machine trap 子集。
`define __INTERRUPT__
`define __RESETPC__ 32'd0
`define RLEN 32

`endif
