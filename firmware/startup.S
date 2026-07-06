    # RISC-V 裸机启动代码。
    # 复位后先设置栈，再清零 .bss，最后跳到 C 的 main()。
    # 这里没有 C runtime，也没有中断/异常入口；它只是最薄的启动骨架。
    .section .init
    .globl _start

_start:
    # linker.ld 提供 _stack_top，栈从 BRAM 顶部向低地址增长。
    la sp, _stack_top

    # C 语言要求全局/静态未初始化变量默认为 0，所以启动阶段必须清 .bss。
    la t0, __bss_start
    la t1, __bss_end

1:
    bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b

2:
    # call 会把返回地址写入 ra；如果 main 意外返回，下面会进入死循环。
    call main

3:
    j 3b
