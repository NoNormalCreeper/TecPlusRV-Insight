// DarkRISCV adapter + custom-0 DOT4 端到端定向测试。
`timescale 1ns/1ps

module tb_darkriscv_dot4 #(
    parameter FIRMWARE_MEM_FILE = "sim/build/darkriscv_dot4.mem"
);

reg clk;
reg resetn;
reg irq_external;
reg irq_timer;
reg ifetch_ready;
reg [31:0] ifetch_rdata;
reg [31:0] imem [0:16383];
reg [31:0] observed [0:127];
reg timer_injected;
integer ack_count;
integer wait_cycles;
integer commit_count;
integer i;

wire ifetch_valid;
wire [31:0] ifetch_addr;
wire mem_valid;
wire mem_instr;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire [3:0] mem_wstrb;
wire [31:0] counter_cycle;
wire [31:0] counter_instret;

darkriscv_adapter dut (
    .clk(clk),
    .resetn(resetn),
    .irq_external(irq_external),
    .irq_timer(irq_timer),
    .ifetch_valid(ifetch_valid),
    .ifetch_addr(ifetch_addr),
    .ifetch_ready(ifetch_ready),
    .ifetch_rdata(ifetch_rdata),
    .mem_valid(mem_valid),
    .mem_instr(mem_instr),
    .mem_ready(1'b1),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(32'h0000_0000),
    .counter_cycle(counter_cycle),
    .counter_instret(counter_instret)
);

always #5 clk = ~clk;

// 与 MiniSoC BRAM 取指口一致：请求后一拍返回数据和 ready。
always @(posedge clk) begin
    if (!resetn) begin
        ifetch_ready <= 1'b0;
        ifetch_rdata <= 32'h0000_0000;
    end else if (ifetch_ready) begin
        ifetch_ready <= 1'b0;
    end else if (ifetch_valid) begin
        ifetch_rdata <= imem[ifetch_addr[15:2]];
        ifetch_ready <= 1'b1;
    end
end

always @(posedge clk) begin
    if (!resetn) begin
        irq_timer <= 1'b0;
        timer_injected <= 1'b0;
        ack_count <= 0;
        wait_cycles <= 0;
        commit_count <= 0;
    end else begin
        if (dut.u_cpu.CPR_REQ && !dut.u_cpu.CPR_ACK) begin
            wait_cycles <= wait_cycles + 1;
            if (!timer_injected) begin
                irq_timer <= 1'b1;
                timer_injected <= 1'b1;
            end
        end
        if (dut.u_cpu.CPR_ACK)
            ack_count <= ack_count + 1;
        if (dut.u_cpu.CPR_REQ && !dut.u_cpu.HLT && !(|dut.u_cpu.FLUSH))
            commit_count <= commit_count + 1;
        if (mem_valid && |mem_wstrb) begin
            observed[mem_addr[8:2]] <= mem_wdata;
            if (mem_addr == 32'h0000_0124)
                irq_timer <= 1'b0;
        end
    end
end

initial begin
    clk = 1'b0;
    resetn = 1'b0;
    irq_external = 1'b0;
    irq_timer = 1'b0;
    ifetch_ready = 1'b0;
    ifetch_rdata = 32'h0000_0000;
    timer_injected = 1'b0;
    ack_count = 0;
    wait_cycles = 0;
    commit_count = 0;
    for (i = 0; i < 128; i = i + 1)
        observed[i] = 32'h0000_0000;
    $readmemh(FIRMWARE_MEM_FILE, imem);

    repeat (8) @(posedge clk);
    resetn = 1'b1;

    wait (observed[32'h13c >> 2] == 32'd1);
    @(posedge clk);
    if (observed[32'h100 >> 2] !== 32'd70 ||
        observed[32'h104 >> 2] !== 32'd1 ||
        observed[32'h108 >> 2] !== -32'sd32515 ||
        observed[32'h10c >> 2] !== 32'd4 ||
        observed[32'h110 >> 2] !== 32'd24 ||
        observed[32'h114 >> 2] !== 32'd0) begin
        $display("FAIL: DOT4 写回/lane/相邻指令错误 s0=%08x s1=%08x s2=%08x s3=%08x s4=%08x x0=%08x",
            observed[32'h100 >> 2], observed[32'h104 >> 2],
            observed[32'h108 >> 2], observed[32'h10c >> 2],
            observed[32'h110 >> 2], observed[32'h114 >> 2]);
        $finish;
    end
    if (observed[32'h120 >> 2] !== 32'd2 ||
        observed[32'h124 >> 2] !== 32'h8000_0007) begin
        $display("FAIL: custom-0 illegal/timer trap 错误 illegal=%08x irq=%08x",
            observed[32'h120 >> 2], observed[32'h124 >> 2]);
        $finish;
    end
    if (ack_count != 5 || commit_count != 5 || wait_cycles < 5 ||
        dut.u_cpu.REGS[0] !== 32'd0) begin
        $display("FAIL: DOT4 transaction/retire/stall/x0 错误 ack=%0d commit=%0d wait=%0d x0=%08x",
            ack_count, commit_count, wait_cycles, dut.u_cpu.REGS[0]);
        $finish;
    end

    $display("PASS: DarkRISCV custom-0 DOT4 写回、停顿与 trap 语义正确");
    $finish;
end

initial begin
    repeat (2000) @(posedge clk);
    $display("TIMEOUT: DarkRISCV DOT4 测试未完成 pc=%08x xidata=%08x ack=%0d wait=%0d illegal=%08x irq=%08x",
        dut.u_cpu.PC, dut.u_cpu.XIDATA, ack_count, wait_cycles,
        observed[32'h120 >> 2], observed[32'h124 >> 2]);
    $finish;
end

endmodule
