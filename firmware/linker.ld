/* TecPlusRV 裸机链接脚本。
 * 当前把代码、只读数据、data、bss 全部放进 0x00000000 起始的 64 KiB BRAM。
 * 这和早期 MiniSoC/仿真的 reset 地址保持一致，后续接 SDRAM 时再扩展内存布局。
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    BRAM (rxw) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS
{
    .text : {
        /* .init 里有 _start，KEEP 防止链接器把入口节优化掉。 */
        KEEP(*(.init))
        *(.text*)
        *(.rodata*)
    } > BRAM

    .data : {
        *(.data*)
    } > BRAM

    .bss : {
        /* startup.S 用这两个符号清零 .bss。 */
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    } > BRAM

    . = ALIGN(16);
    /* 栈顶放在 BRAM 末尾；RISC-V ABI 推荐 16-byte 对齐。 */
    _stack_top = ORIGIN(BRAM) + LENGTH(BRAM);
}
