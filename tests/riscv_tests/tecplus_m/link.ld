/* DarkRISCV rv32mi 专用链接脚本：reset/.text.init 固定从 0 开始。 */
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
        KEEP(*(.text.init))
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
