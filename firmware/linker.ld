/* TecPlusRV 裸机链接脚本。
 * 代码 / 只读数据 / .data / .bss / 栈仍然放在 0x00000000 起始的 64 KiB BRAM，
 * 这与仿真的 reset 地址一致。
 *
 * M3 新增：SDRAM 数据窗口（0x8000_0000），以及可显式落到 SDRAM 的
 * .sdram_data / .sdram_bss 段。
 *
 * 容量说明：板上物理芯片为 x16 SDRAM，地址线 A0..A12（13 位 row，见
 * constraints/tecplus_sdram_smoke.ucf），控制器使用 byte_addr[24:1]，
 * 因此 U2 的 32 MiB 空间全部可达。
 *   - .sdram_data：有初值，运行地址在 SDRAM，加载地址在 BRAM（AT> 分离），
 *     由 startup.S 在复位后从加载地址拷到运行地址。
 *   - .sdram_bss ：运行时清零，NOLOAD 不占 firmware 镜像。
 *
 * heap：M3 阶段先放 BRAM，让 bump allocator 在现有 minisoc 仿真里就能真跑通。
 * 等 SoC 侧把 0x8000_0000 接上总线（M2b）后，只需把下面 `.heap` 的
 * 归属从 `> BRAM` 改成 `> SDRAM`（单点开关），无需改动 allocator 代码。
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    BRAM  (rxw) : ORIGIN = 0x00000000, LENGTH = 64K
    SDRAM (rw)  : ORIGIN = 0x80000000, LENGTH = 32M
}

/* heap 预留大小（放在 BRAM 内，位于 .bss 之后、栈之前）。 */
_heap_size = 8K;

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

    /* bump allocator 的 heap 区。M3 阶段落在 BRAM，符号供 alloc.c 使用。 */
    .heap (NOLOAD) : {
        . = ALIGN(16);
        _heap_start = .;
        . = . + _heap_size;
        _heap_end = .;
    } > BRAM

    . = ALIGN(16);
    /* 栈顶放在 BRAM 末尾；RISC-V ABI 推荐 16-byte 对齐。 */
    _stack_top = ORIGIN(BRAM) + LENGTH(BRAM);

    /* ---- SDRAM 数据窗口 ----
     * 显式标注 __attribute__((section(".sdram_data"))) 的有初值对象放这里；
     * 运行地址在 SDRAM，加载地址在 BRAM，由 startup.S 搬运。
     */
    .sdram_data : {
        . = ALIGN(4);
        _sdram_data_start = .;
        *(.sdram_data*)
        . = ALIGN(4);
        _sdram_data_end = .;
    } > SDRAM AT> BRAM
    _sdram_data_load_start = LOADADDR(.sdram_data);

    /* 标注 .sdram_bss 的对象放这里，运行时由 startup.S 清零。NOLOAD 不占镜像。 */
    .sdram_bss (NOLOAD) : {
        . = ALIGN(4);
        _sdram_bss_start = .;
        *(.sdram_bss*)
        . = ALIGN(4);
        _sdram_bss_end = .;
    } > SDRAM
}
