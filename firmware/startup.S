    # RISC-V 裸机启动代码。
    # 复位后：设栈 -> 搬运 .data -> 清 .bss -> 搬运 .sdram_data -> 清 .sdram_bss -> 跳 main()。
    # 这里没有 C runtime，也没有中断/异常入口；它只是最薄的启动骨架。
    #
    # M3 新增：
    #   - .data 拷贝：LMA/VMA 使用 BRAM 内两个相邻槽位，启动时真实搬运。
    #   - .sdram_data 拷贝：SDRAM 上电内容随机，不像 BRAM 由 firmware.mem 初始化，
    #     所以有初值、运行地址在 SDRAM 的对象必须在这里从加载地址（BRAM）拷到运行地址。
    #   - .sdram_bss 清零：与 .bss 同理，运行时清零。
    .section .init
    .globl _start

_start:
    # linker.ld 提供 _stack_top，栈从 BRAM 顶部向低地址增长。
    la sp, _stack_top

    # 搬运 .data：从加载地址（LMA）逐字拷到运行地址（VMA）。
    la t0, __data_load_start
    la t1, __data_start
    la t2, __data_end

1:
    bgeu t1, t2, 2f
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j 1b

2:
    # C 语言要求全局/静态未初始化变量默认为 0，所以启动阶段必须清 .bss。
    la t0, __bss_start
    la t1, __bss_end

3:
    bgeu t0, t1, 4f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 3b

4:
    # 搬运 .sdram_data：从加载地址（LMA，在 BRAM）逐字拷到运行地址（VMA，在 SDRAM）。
    # t0=源(load)，t1=目的(run 起点)，t2=目的结束。逐字拷贝，段边界已按 4 字节对齐。
    la t0, _sdram_data_load_start
    la t1, _sdram_data_start
    la t2, _sdram_data_end

5:
    bgeu t1, t2, 6f
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j 5b

6:
    # 清 .sdram_bss：运行时清零，语义同 .bss。
    la t0, _sdram_bss_start
    la t1, _sdram_bss_end

7:
    bgeu t0, t1, 8f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 7b

8:
    # call 会把返回地址写入 ra；如果 main 意外返回，下面会进入死循环。
    call main

9:
    j 9b
