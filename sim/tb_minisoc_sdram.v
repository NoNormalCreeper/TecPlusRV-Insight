// MiniSoC SDRAM 集成测试：真实 CPU 经板级 sh_* 接口完成多地址写读回。
`timescale 1ns/1ps

module tb_minisoc_sdram #(
    parameter integer CPU_IMPL = 0,
    parameter FIRMWARE_MEM_FILE = "firmware/build/firmware.mem",
    parameter integer TIMEOUT_CYCLES = 5000000
);

reg clk;
reg reset;
reg [3:0] key;
reg uart_rxd;

wire [3:0] led;
wire uart_txd;
wire [11:0] tl;
wire spk;
wire sh_clk;
wire sh_cke;
wire sh_ncs;
wire sh_nwe;
wire sh_ncas;
wire sh_nras;
wire [1:0] sh_dqm;
wire [1:0] sh_ba;
wire [12:0] sh_a;
wire [15:0] sh_db;
wire [31:0] model_read_command_count;
wire [31:0] model_write_command_count;

integer accepted_read_count;
integer accepted_write_count;
integer response_count;
integer cycle_count;
integer bram_route_count;
integer mmio_route_count;
integer sdram_route_count;
integer ifetch_count;

tecplus_minisoc_top #(
    .CLK_FREQ(1000000),
    .UART_BAUD(100000),
    .CPU_IMPL(CPU_IMPL),
    .BRAM_ADDR_WIDTH(14),
    .BRAM_INIT_FILE(FIRMWARE_MEM_FILE)
) dut (
    .clk(clk),
    .reset(reset),
    .key(key),
    .led(led),
    .uart_rxd(uart_rxd),
    .uart_txd(uart_txd),
    .tl(tl),
    .spk(spk),
    .sh_clk(sh_clk),
    .sh_cke(sh_cke),
    .sh_ncs(sh_ncs),
    .sh_nwe(sh_nwe),
    .sh_ncas(sh_ncas),
    .sh_nras(sh_nras),
    .sh_dqm(sh_dqm),
    .sh_ba(sh_ba),
    .sh_a(sh_a),
    .sh_db(sh_db)
);

sdram_x16_model model (
    .clk(clk),
    .reset(!reset),
    .cke(sh_cke),
    .cs_n(sh_ncs),
    .ras_n(sh_nras),
    .cas_n(sh_ncas),
    .we_n(sh_nwe),
    .dqm(sh_dqm),
    .ba(sh_ba),
    .addr(sh_a),
    .dq(sh_db),
    .read_command_count(model_read_command_count),
    .write_command_count(model_write_command_count)
);

always #5 clk = ~clk;

initial begin
    clk = 1'b0;
    reset = 1'b0;
    key = 4'b1111;
    uart_rxd = 1'b1;
    accepted_read_count = 0;
    accepted_write_count = 0;
    response_count = 0;
    cycle_count = 0;
    bram_route_count = 0;
    mmio_route_count = 0;
    sdram_route_count = 0;
    ifetch_count = 0;
    repeat (5) @(posedge clk);
    reset = 1'b1;
end

always @(posedge clk) begin
    cycle_count = cycle_count + 1;

    if (reset && dut.start_req) begin
        case ({dut.is_bram, dut.is_mmio, dut.is_sdram})
            3'b100: begin
                bram_route_count = bram_route_count + 1;
                if (dut.bram_en !== 1'b1) begin
                    $display("FAIL: BRAM 请求没有命中 BRAM");
                    $finish;
                end
            end
            3'b010: mmio_route_count = mmio_route_count + 1;
            3'b001: begin
                sdram_route_count = sdram_route_count + 1;
                if (dut.bram_en !== 1'b0 || dut.u_decode.valid !== 1'b0) begin
                    $display("FAIL: SDRAM 地址 %08x 串入 BRAM/TinyBus", dut.mem_addr);
                    $finish;
                end
            end
            default: begin
                $display("FAIL: 地址三分流不是 one-hot，addr=%08x route=%b%b%b",
                         dut.mem_addr, dut.is_bram, dut.is_mmio, dut.is_sdram);
                $finish;
            end
        endcase
    end

    if (reset && dut.pending) begin
        case ({dut.req_is_bram, dut.req_is_mmio, dut.req_is_sdram})
            3'b100, 3'b010, 3'b001: begin
            end
            default: begin
                $display("FAIL: 已锁存请求的三分流不是 one-hot，addr=%08x route=%b%b%b",
                         dut.req_addr, dut.req_is_bram, dut.req_is_mmio, dut.req_is_sdram);
                $finish;
            end
        endcase

        if (dut.req_is_mmio) begin
            if (dut.u_decode.valid !== 1'b1) begin
                $display("FAIL: MMIO 请求没有进入 tinybus_decode，addr=%08x", dut.req_addr);
                $finish;
            end
        end else if (dut.u_decode.valid !== 1'b0) begin
            $display("FAIL: 非 MMIO 请求误入 tinybus_decode，addr=%08x", dut.req_addr);
            $finish;
        end

        if (dut.req_is_sdram && dut.bram_en !== 1'b0) begin
            $display("FAIL: SDRAM 请求误使能 BRAM，addr=%08x", dut.req_addr);
            $finish;
        end
    end

    if (reset && dut.ifetch_rdata !== dut.ifetch_bram_rdata) begin
        $display("FAIL: ifetch_rdata 不再直接来自 BRAM");
        $finish;
    end

    if (reset && dut.ifetch_valid) begin
        ifetch_count = ifetch_count + 1;
        if (dut.ifetch_is_bram !== 1'b1 || dut.ifetch_en !== !dut.ifetch_pending) begin
            $display("FAIL: ifetch 请求没有保持在 BRAM，addr=%08x", dut.ifetch_addr);
            $finish;
        end
    end

    if (dut.sdram_req_fire) begin
        if (dut.req_we_reg)
            accepted_write_count = accepted_write_count + 1;
        else
            accepted_read_count = accepted_read_count + 1;
    end
    if (dut.sdram_resp_valid) begin
        response_count = response_count + 1;
    end
end

initial begin
    repeat (TIMEOUT_CYCLES) begin
        @(posedge clk);
        if (dut.test_exited) begin
            if (dut.test_exit_code !== 32'h0000_0001) begin
                $display("FAIL: SDRAM firmware test_exit=0x%08x", dut.test_exit_code);
                $finish;
            end
            if (led !== 4'h5) begin
                $display("FAIL: SDRAM firmware LED=%h，期望 5", led);
                $finish;
            end
            if (accepted_read_count == 0 || accepted_write_count == 0) begin
                $display("FAIL: SDRAM 集成测试没有同时覆盖 read/write");
                $finish;
            end
            if (bram_route_count == 0 || mmio_route_count == 0 || sdram_route_count == 0) begin
                $display("FAIL: 地址三分流覆盖不完整 bram=%0d mmio=%0d sdram=%0d",
                         bram_route_count, mmio_route_count, sdram_route_count);
                $finish;
            end
            if ((CPU_IMPL == 0 && ifetch_count != 0) ||
                (CPU_IMPL != 0 && ifetch_count == 0)) begin
                $display("FAIL: ifetch 覆盖不符合 CPU wrapper 契约 cpu=%0d count=%0d",
                         CPU_IMPL, ifetch_count);
                $finish;
            end
            if (response_count != accepted_read_count + accepted_write_count) begin
                $display("FAIL: SDRAM 请求/响应数量不一致 req=%0d resp=%0d",
                         accepted_read_count + accepted_write_count, response_count);
                $finish;
            end
            if (model_read_command_count != accepted_read_count * 2) begin
                $display("FAIL: 每笔 32-bit read 应产生两个 x16 READ，req=%0d cmd=%0d",
                         accepted_read_count, model_read_command_count);
                $finish;
            end
            if (model_write_command_count != accepted_write_count * 2) begin
                $display("FAIL: 每笔 32-bit write 应产生两个 x16 WRITE，req=%0d cmd=%0d",
                         accepted_write_count, model_write_command_count);
                $finish;
            end
            $display("PASS: MiniSoC SDRAM 集成通过，cycle=%0d read=%0d write=%0d bram=%0d mmio=%0d sdram=%0d ifetch=%0d",
                     cycle_count, accepted_read_count, accepted_write_count,
                     bram_route_count, mmio_route_count, sdram_route_count, ifetch_count);
            $finish;
        end
    end
    $display("TIMEOUT: MiniSoC SDRAM 未退出 cycle=%0d read=%0d write=%0d resp=%0d pending=%b sent=%b ctrl_state=%0d mem_addr=%08x",
             cycle_count, accepted_read_count, accepted_write_count, response_count,
             dut.pending, dut.sdram_req_sent, dut.u_sdram.dbg_state, dut.mem_addr);
    $finish;
end

// 将 firmware 的 UART 输出还原到仿真终端，保留 benchmark 的 cycle/instret 证据。
localparam integer UART_CLKS_PER_BIT = 1000000 / 100000;
localparam integer UART_CLK_PERIOD_NS = 10;
localparam integer UART_BIT_NS = UART_CLKS_PER_BIT * UART_CLK_PERIOD_NS;

integer uart_bit_i;
reg [7:0] uart_rx_byte;

initial begin
    forever begin
        @(negedge uart_txd);
        #(UART_BIT_NS + UART_BIT_NS / 2);
        for (uart_bit_i = 0; uart_bit_i < 8; uart_bit_i = uart_bit_i + 1) begin
            uart_rx_byte[uart_bit_i] = uart_txd;
            #(UART_BIT_NS);
        end
        $write("%c", uart_rx_byte);
        $fflush;
    end
end

endmodule
