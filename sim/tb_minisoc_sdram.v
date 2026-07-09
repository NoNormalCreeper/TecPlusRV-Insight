// MiniSoC SDRAM 集成测试：验证 CPU 对 0x8000_0000 区域的读写。
`timescale 1ns/1ps

module tb_minisoc_sdram #(
    parameter CPU_IMPL = 0
);

reg clk;
reg reset;
reg [3:0] key;
reg uart_rxd;

wire [3:0] led;
wire uart_txd;
wire [11:0] tl;

tecplus_minisoc_top #(
    .CLK_FREQ(1000000),
    .UART_BAUD(100000),
    .CPU_IMPL(CPU_IMPL),
    .BRAM_ADDR_WIDTH(14),
    .BRAM_INIT_FILE("firmware/build/test_sdram.mem")
) dut (
    .clk(clk),
    .reset(reset),
    .key(key),
    .led(led),
    .uart_rxd(uart_rxd),
    .uart_txd(uart_txd),
    .tl(tl)
);

always #5 clk = ~clk;

// ===== 启动打印（重要！） =====
initial begin
    $display("=== tb_minisoc_sdram started ===");
    clk = 1'b0;
    reset = 1'b0;
    key = 4'b1111;
    uart_rxd = 1'b1;
    $dumpfile("sim/build/tb_minisoc_sdram.vcd");
    $dumpvars(0, tb_minisoc_sdram);
    repeat (5) @(posedge clk);
    reset = 1'b1;
    $display("=== reset released ===");
end

// ===== 超时监测 + PASS/FAIL =====
initial begin
    repeat (5000000) begin
        @(posedge clk);
        if (dut.test_exited) begin
            if (dut.test_exit_code !== 32'h0000_0001) begin
                $display("FAIL: test_exit=0x%08x", dut.test_exit_code);
                $finish;
            end
            if (led !== 4'h5) begin
                $display("FAIL: LED = %h, expected 5", led);
                $finish;
            end
            $display("PASS: SDRAM read/write test passed, LED=5");
            $finish;
        end
    end
    $display("TIMEOUT: SDRAM test did not reach test_exit");
    $finish;
end

// ===== SDRAM 响应监测（调试用） =====
always @(posedge clk) begin
    if (dut.u_sdram.resp_valid) begin
        $display("SDRAM resp_valid at time %t", $time);
    end
end

// ===== 非阻塞 UART 监听器（使用定时采样，避免 forever 死锁） =====
reg [7:0] uart_rx_byte;
reg       uart_sampling;
integer   uart_bit_i;
integer   uart_clk_count;

initial begin
    uart_sampling = 1'b0;
    uart_clk_count = 0;
    uart_rx_byte = 8'h00;
end

always @(posedge clk) begin
    // 空闲时等待下降沿
    if (!uart_sampling && uart_txd == 1'b0) begin
        uart_sampling = 1'b1;
        uart_clk_count = 0;
        uart_bit_i = 0;
    end

    if (uart_sampling) begin
        uart_clk_count = uart_clk_count + 1;
        
        // 起始位采样（跳过半个 bit）
        if (uart_clk_count == 5) begin
            // 开始采样数据位
            uart_bit_i = 0;
        end
        
        // 每 10 个时钟采样一个数据位
        if (uart_clk_count >= 5 && (uart_clk_count - 5) % 10 == 0 && uart_bit_i < 8) begin
            uart_rx_byte[uart_bit_i] = uart_txd;
            uart_bit_i = uart_bit_i + 1;
        end
        
        // 8 个数据位采完，输出字符
        if (uart_bit_i == 8) begin
            $write("%c", uart_rx_byte);
            $fflush;
            uart_sampling = 1'b0;
            uart_clk_count = 0;
            uart_bit_i = 0;
        end
        
        // 超时保护：如果超过 100 个时钟还没采完，复位状态机
        if (uart_clk_count > 200) begin
            uart_sampling = 1'b0;
            uart_clk_count = 0;
            uart_bit_i = 0;
        end
    end
end
always @(posedge clk) begin
    if (dut.u_sdram.req_valid && dut.u_sdram.req_ready) begin
        $display("SDRAM request accepted at %t", $time);
    end
    if (dut.u_sdram.resp_valid) begin
        $display("SDRAM response at %t", $time);
    end
    if (dut.mem_ready) begin
        $display("mem_ready at %t", $time);
    end
end


endmodule