OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    BRAM (rxw) : ORIGIN = 0x00000000, LENGTH = 8K
}

SECTIONS
{
    .text : {
        KEEP(*(.init))
        *(.text*)
        *(.rodata*)
    } > BRAM

    .data : {
        *(.data*)
    } > BRAM

    .bss : {
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    } > BRAM

    . = ALIGN(16);
    _stack_top = ORIGIN(BRAM) + LENGTH(BRAM);
}

