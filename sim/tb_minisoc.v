// MiniSoC 的临时骨架仿真。
// 如果 rtl/core/picorv32.v 存在，就直接实例化 PicoRV32 native memory interface；
// 如果不存在，输出 SKIP，避免把缺外部核误判成项目失败。
`timescale 1ns/1ps

module tb_minisoc;

`ifdef PICORV32_PRESENT
reg clk;
reg resetn;

wire        mem_valid;
wire        mem_instr;
reg         mem_ready;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire [3:0]  mem_wstrb;
reg  [31:0] mem_rdata;

reg  [31:0] mem [0:2047];
reg         exited;
reg  [31:0] exit_code;
integer     cycle_count;
integer     word_index;

initial begin
    clk = 1'b0;
    resetn = 1'b0;
    mem_ready = 1'b0;
    mem_rdata = 32'h0000_0000;
    exited = 1'b0;
    exit_code = 32'h0000_0000;
    cycle_count = 0;

    for (word_index = 0; word_index < 2048; word_index = word_index + 1) begin
        mem[word_index] = 32'h0000_0000;
    end

    // build_firmware.sh 生成的 firmware.mem 是 little-endian 32-bit word 文本。
    $readmemh("firmware/build/firmware.mem", mem);
    #100;
    resetn = 1'b1;
end

always #5 clk = ~clk;

always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    mem_ready <= 1'b0;

    if (mem_valid) begin
        mem_ready <= 1'b1;

        if (mem_addr[31:13] == 19'h0) begin
            // 0x0000_0000 起的 8 KiB 模拟 BRAM，地址按 word 对齐取 mem_addr[12:2]。
            if (mem_wstrb[0]) mem[mem_addr[12:2]][7:0] <= mem_wdata[7:0];
            if (mem_wstrb[1]) mem[mem_addr[12:2]][15:8] <= mem_wdata[15:8];
            if (mem_wstrb[2]) mem[mem_addr[12:2]][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) mem[mem_addr[12:2]][31:24] <= mem_wdata[31:24];
            mem_rdata <= mem[mem_addr[12:2]];
        end else if (mem_addr == 32'h1000_0030 && mem_wstrb != 4'b0000) begin
            // 软件写 test_exit 后，testbench 根据写入值判断 PASS/FAIL。
            exited <= 1'b1;
            exit_code <= mem_wdata;
            mem_rdata <= 32'h0000_0000;
        end else if (mem_addr == 32'h1000_0014) begin
            // UART_STATUS 固定返回 ready，保证 firmware 的阻塞发送能继续前进。
            mem_rdata <= 32'h0000_0001;
        end else begin
            mem_rdata <= 32'h0000_0000;
        end
    end

    if (exited) begin
        if (exit_code == 32'h0000_0001) begin
            $display("PASS: test_exit=0x%08x，周期数=%0d", exit_code, cycle_count);
            $finish;
        end else begin
            $display("FAIL: test_exit=0x%08x，周期数=%0d", exit_code, cycle_count);
            $finish;
        end
    end

    if (cycle_count > 200000) begin
        $display("TIMEOUT: 没有到达 test_exit");
        $finish;
    end
end

picorv32 #(
    .ENABLE_COUNTERS(0),
    .ENABLE_COUNTERS64(0),
    .ENABLE_REGS_DUALPORT(0),
    .ENABLE_MUL(0),
    .ENABLE_DIV(0),
    .ENABLE_IRQ(0),
    .ENABLE_COMPRESSED(0),
    .PROGADDR_RESET(32'h0000_0000),
    .STACKADDR(32'h0000_2000)
) uut (
    .clk(clk),
    .resetn(resetn),
    .trap(),
    .mem_valid(mem_valid),
    .mem_instr(mem_instr),
    .mem_ready(mem_ready),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(mem_rdata),
    .irq(32'h0000_0000),
    .eoi(),
    .trace_valid(),
    .trace_data()
);
`else
initial begin
    $display("SKIP: 缺少 rtl/core/picorv32.v，请先引入 PicoRV32 再运行 MiniSoC 仿真");
    $finish;
end
`endif

endmodule
