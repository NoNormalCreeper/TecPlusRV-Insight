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
 *   - .data：有初值，运行地址与加载地址当前都在 BRAM，但仍导出 LMA/VMA
 *     边界并由 startup.S 执行拷贝，后续迁移内存布局时不用重写启动流程。
 *   - .sdram_data：有初值，运行地址在 SDRAM，加载地址在 BRAM（AT> 分离），
 *     由 startup.S 在复位后从加载地址拷到运行地址。
 *   - .sdram_bss ：运行时清零，NOLOAD 不占 firmware 镜像。
 *
 * heap：M2b 接通 0x8000_0000 后，heap 落在 SDRAM（bump allocator 的线性池），
 * BRAM 只保留 .text/.data/.bss/栈。切换 heap 归属只需改下面 `.heap` 的
 * 内存区这一处（单点开关），allocator 代码无需改动。
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    BRAM  (rxw) : ORIGIN = 0x00000000, LENGTH = 64K
    SDRAM (rw)  : ORIGIN = 0x80000000, LENGTH = 32M
}

/* heap 预留大小（放在 SDRAM 内，位于 .sdram_bss 之后）。 */
_heap_size = 64K;

SECTIONS
{
    .text : {
        /* .init 里有 _start，KEEP 防止链接器把入口节优化掉。 */
        KEEP(*(.init))
        *(.text*)
        *(.rodata*)
    } > BRAM

    . = ALIGN(4);
    .data : {
        __data_start = .;
        *(.sdata*)
        *(.data*)
        . = ALIGN(4);
        __data_end = .;
    } > BRAM AT> BRAM
    __data_load_start = LOADADDR(.data);

    .bss : {
        /* startup.S 用这两个符号清零 .bss。 */
        __bss_start = .;
        *(.sbss*)
        *(.bss*)
        *(COMMON)
        __bss_end = .;
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

    /* bump allocator 的 heap 区。M2b 后落在 SDRAM，位于 .sdram_bss 之后。
     * NOLOAD：不占 firmware 镜像；符号 _heap_start/_heap_end 供 rt_alloc.c 使用。 */
    .heap (NOLOAD) : {
        . = ALIGN(16);
        _heap_start = .;
        . = . + _heap_size;
        _heap_end = .;
    } > SDRAM
}
