/* TecPlusRV riscv-tests 专用链接脚本。
 * 当前把代码/数据/签名区全部放到 0x0000_0000 起始的 64 KiB BRAM。
 * 这是为了直接复用现有 MiniSoC reset 地址与 BRAM 仿真路径。
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    BRAM (rxw) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS
{
    . = ORIGIN(BRAM);

    .text.init : {
        *(.text.init)
    } > BRAM

    .text : {
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
    } > BRAM

    .data : {
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
    } > BRAM

    .bss : {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > BRAM

    . = ALIGN(16);
    _stack_top = ORIGIN(BRAM) + LENGTH(BRAM);
}
