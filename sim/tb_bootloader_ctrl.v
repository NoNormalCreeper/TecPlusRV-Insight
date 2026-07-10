// bootloader_ctrl 协议与错误恢复测试。
`timescale 1ns/1ps

module tb_bootloader_ctrl;

localparam integer ADDR_WIDTH = 4;
localparam integer TIMEOUT_CYCLES = 30;

reg clk;
reg reset;
reg [7:0] rx_data;
reg rx_valid;
reg rx_overrun;
reg rx_framing_error;
wire rx_ready;
wire clear_rx_overrun;
wire clear_rx_framing_error;
reg tx_ready;
wire tx_valid;
wire [7:0] tx_data;
wire bram_en;
wire [ADDR_WIDTH-1:0] bram_addr;
wire [31:0] bram_wdata;
wire [3:0] bram_wstrb;
wire sdram_req_valid;
reg sdram_req_ready;
wire [31:0] sdram_req_addr;
wire [31:0] sdram_req_wdata;
wire [3:0] sdram_req_wstrb;
reg sdram_resp_valid;
reg sdram_resp_error;
wire cpu_release;
wire [7:0] last_error;

reg [31:0] mem [0:(1 << ADDR_WIDTH) - 1];
reg [31:0] sdram_mem [0:3];
reg sdram_response_pending;
reg [7:0] responses [0:31];
integer response_count;
integer tx_busy_count;
integer i;
reg [31:0] test_crc;

bootloader_ctrl #(
    .BRAM_ADDR_WIDTH(ADDR_WIDTH),
    .INTERBYTE_TIMEOUT_CYCLES(TIMEOUT_CYCLES)
) dut (
    .clk(clk),
    .reset(reset),
    .rx_data(rx_data),
    .rx_valid(rx_valid),
    .rx_overrun(rx_overrun),
    .rx_framing_error(rx_framing_error),
    .rx_ready(rx_ready),
    .clear_rx_overrun(clear_rx_overrun),
    .clear_rx_framing_error(clear_rx_framing_error),
    .tx_ready(tx_ready),
    .tx_valid(tx_valid),
    .tx_data(tx_data),
    .bram_en(bram_en),
    .bram_addr(bram_addr),
    .bram_wdata(bram_wdata),
    .bram_wstrb(bram_wstrb),
    .sdram_req_valid(sdram_req_valid),
    .sdram_req_ready(sdram_req_ready),
    .sdram_req_addr(sdram_req_addr),
    .sdram_req_wdata(sdram_req_wdata),
    .sdram_req_wstrb(sdram_req_wstrb),
    .sdram_resp_valid(sdram_resp_valid),
    .sdram_resp_error(sdram_resp_error),
    .cpu_release(cpu_release),
    .last_error(last_error)
);

always #5 clk = ~clk;

always @(posedge clk) begin
    if (bram_en) begin
        if (bram_wstrb[0]) mem[bram_addr][7:0] <= bram_wdata[7:0];
        if (bram_wstrb[1]) mem[bram_addr][15:8] <= bram_wdata[15:8];
        if (bram_wstrb[2]) mem[bram_addr][23:16] <= bram_wdata[23:16];
        if (bram_wstrb[3]) mem[bram_addr][31:24] <= bram_wdata[31:24];
    end
end

// 用一个最小 ready-first 模型检查 bootloader 发出的 SDRAM word write。
always @(posedge clk) begin
    if (reset) begin
        sdram_resp_valid <= 1'b0;
        sdram_response_pending <= 1'b0;
    end else begin
        sdram_resp_valid <= sdram_response_pending;
        sdram_response_pending <= 1'b0;
        if (sdram_req_valid && sdram_req_ready) begin
            if (sdram_req_addr < 32'h8100_0000 || sdram_req_addr >= 32'h8100_0010) begin
                $display("FAIL: SDRAM 地址越界：%08x", sdram_req_addr);
                $finish;
            end
            sdram_mem[(sdram_req_addr - 32'h8100_0000) >> 2] <= sdram_req_wdata;
            sdram_response_pending <= 1'b1;
        end
    end
end

// 模拟现有 uart_tx 的 ready 行为，并记录控制器发送的两字节响应。
always @(posedge clk) begin
    if (reset) begin
        tx_ready <= 1'b1;
        tx_busy_count <= 0;
    end else if (tx_ready && tx_valid) begin
        responses[response_count] <= tx_data;
        response_count <= response_count + 1;
        tx_ready <= 1'b0;
        tx_busy_count <= 2;
    end else if (!tx_ready) begin
        if (tx_busy_count == 0)
            tx_ready <= 1'b1;
        else
            tx_busy_count <= tx_busy_count - 1;
    end
end

function [31:0] crc32_byte;
    input [31:0] crc;
    input [7:0] data;
    reg [31:0] value;
    integer bit_index;
    begin
        value = crc ^ {24'h000000, data};
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            if (value[0])
                value = (value >> 1) ^ 32'hedb88320;
            else
                value = value >> 1;
        end
        crc32_byte = value;
    end
endfunction

task send_byte;
    input [7:0] value;
    begin
        while (!rx_ready)
            @(posedge clk);
        @(negedge clk);
        rx_data = value;
        rx_valid = 1'b1;
        @(negedge clk);
        rx_valid = 1'b0;
    end
endtask

task send_image_packet;
    reg [31:0] crc;
    reg [31:0] final_crc;
    reg [7:0] value;
    integer byte_i;
    begin
        send_magic();
        crc = 32'hffff_ffff;

        send_byte(8'h01); crc = crc32_byte(crc, 8'h01);
        send_byte(8'h02); crc = crc32_byte(crc, 8'h02);

        // BRAM payload 长度：8 bytes。
        send_byte(8'h08); crc = crc32_byte(crc, 8'h08);
        send_byte(8'h00); crc = crc32_byte(crc, 8'h00);
        send_byte(8'h00); crc = crc32_byte(crc, 8'h00);
        send_byte(8'h00); crc = crc32_byte(crc, 8'h00);

        // SDRAM 目标地址：0x81000000，payload 长度：8 bytes。
        send_byte(8'h00); crc = crc32_byte(crc, 8'h00);
        send_byte(8'h00); crc = crc32_byte(crc, 8'h00);
        send_byte(8'h00); crc = crc32_byte(crc, 8'h00);
        send_byte(8'h81); crc = crc32_byte(crc, 8'h81);
        send_byte(8'h08); crc = crc32_byte(crc, 8'h08);
        send_byte(8'h00); crc = crc32_byte(crc, 8'h00);
        send_byte(8'h00); crc = crc32_byte(crc, 8'h00);
        send_byte(8'h00); crc = crc32_byte(crc, 8'h00);

        for (byte_i = 0; byte_i < 8; byte_i = byte_i + 1) begin
            value = 8'hc0 + byte_i;
            send_byte(value);
            crc = crc32_byte(crc, value);
        end
        for (byte_i = 0; byte_i < 8; byte_i = byte_i + 1) begin
            value = 8'he0 + byte_i;
            send_byte(value);
            crc = crc32_byte(crc, value);
        end

        final_crc = ~crc;
        send_byte(final_crc[7:0]);
        send_byte(final_crc[15:8]);
        send_byte(final_crc[23:16]);
        send_byte(final_crc[31:24]);
    end
endtask

task send_magic;
    begin
        send_byte(8'h1e);
        send_byte(8'hbb);
        send_byte(8'hda);
        send_byte(8'hba);
    end
endtask

task send_packet;
    input [7:0] payload_base;
    input       corrupt_crc;
    reg [31:0] crc;
    reg [31:0] final_crc;
    reg [7:0] payload_byte;
    integer payload_i;
    begin
        send_magic();
        crc = 32'hffff_ffff;

        send_byte(8'h01);
        crc = crc32_byte(crc, 8'h01);
        send_byte(8'h01);
        crc = crc32_byte(crc, 8'h01);

        send_byte(8'h08);
        crc = crc32_byte(crc, 8'h08);
        send_byte(8'h00);
        crc = crc32_byte(crc, 8'h00);
        send_byte(8'h00);
        crc = crc32_byte(crc, 8'h00);
        send_byte(8'h00);
        crc = crc32_byte(crc, 8'h00);

        for (payload_i = 0; payload_i < 8; payload_i = payload_i + 1) begin
            payload_byte = payload_base + payload_i;
            send_byte(payload_byte);
            crc = crc32_byte(crc, payload_byte);
        end

        final_crc = ~crc;
        if (corrupt_crc)
            final_crc = final_crc ^ 32'h0000_0001;
        send_byte(final_crc[7:0]);
        send_byte(final_crc[15:8]);
        send_byte(final_crc[23:16]);
        send_byte(final_crc[31:24]);
    end
endtask

task wait_responses;
    input integer expected_count;
    integer wait_cycles;
    begin
        wait_cycles = 0;
        while (response_count < expected_count && wait_cycles < 1000) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end
        if (response_count < expected_count) begin
            $display("TIMEOUT: 期望 %0d 个响应字节，实际只有 %0d 个", expected_count, response_count);
            $finish;
        end
    end
endtask

task expect_response;
    input integer index;
    input [7:0] first;
    input [7:0] second;
    begin
        wait_responses(index + 2);
        if (responses[index] !== first || responses[index + 1] !== second) begin
            $display("FAIL: response[%0d]=%02x %02x，期望 %02x %02x",
                     index, responses[index], responses[index + 1], first, second);
            $finish;
        end
    end
endtask

initial begin
    clk = 1'b0;
    reset = 1'b1;
    rx_data = 8'h00;
    rx_valid = 1'b0;
    rx_overrun = 1'b0;
    rx_framing_error = 1'b0;
    tx_ready = 1'b1;
    response_count = 0;
    tx_busy_count = 0;
    sdram_req_ready = 1'b1;
    sdram_resp_valid = 1'b0;
    sdram_resp_error = 1'b0;
    sdram_response_pending = 1'b0;
    test_crc = 32'hffff_ffff;
    for (i = 0; i < (1 << ADDR_WIDTH); i = i + 1)
        mem[i] = 32'hdead_beef;
    for (i = 0; i < 4; i = i + 1)
        sdram_mem[i] = 32'hdead_beef;

    $dumpfile("sim/build/tb_bootloader_ctrl.vcd");
    $dumpvars(0, tb_bootloader_ctrl);

    // 固定标准向量，避免 RTL 与 testbench 同时实现了同一种错误 CRC 算法。
    test_crc = crc32_byte(test_crc, "1");
    test_crc = crc32_byte(test_crc, "2");
    test_crc = crc32_byte(test_crc, "3");
    test_crc = crc32_byte(test_crc, "4");
    test_crc = crc32_byte(test_crc, "5");
    test_crc = crc32_byte(test_crc, "6");
    test_crc = crc32_byte(test_crc, "7");
    test_crc = crc32_byte(test_crc, "8");
    test_crc = crc32_byte(test_crc, "9");
    if (~test_crc !== 32'hcbf4_3926) begin
        $display("FAIL: CRC32 标准向量不匹配：%08x", ~test_crc);
        $finish;
    end

    repeat (4) @(posedge clk);
    reset = 1'b0;

    // RESET 后先清空 BRAM，再发 READY。
    expect_response(0, 8'h52, 8'h00);
    for (i = 0; i < (1 << ADDR_WIDTH); i = i + 1) begin
        if (mem[i] !== 32'h0000_0000) begin
            $display("FAIL: 初始清零遗漏 mem[%0d]=%08x", i, mem[i]);
            $finish;
        end
    end

    // magic 前允许存在噪声；找到 magic 后拒绝错误版本。
    send_byte(8'h00);
    send_byte(8'h1e);
    send_byte(8'h00);
    send_magic();
    send_byte(8'h02);
    expect_response(2, 8'h1f, 8'h01);
    if (cpu_release || last_error !== 8'h01) begin
        $display("FAIL: 错误版本释放了 CPU 或丢失错误码");
        $finish;
    end

    // 64-byte BRAM 拒绝 65-byte payload。
    send_magic();
    send_byte(8'h01);
    send_byte(8'h01);
    send_byte(8'h41);
    send_byte(8'h00);
    send_byte(8'h00);
    send_byte(8'h00);
    expect_response(4, 8'h1f, 8'h02);

    // UART sticky error 会清除并返回明确错误码。
    send_magic();
    @(negedge clk);
    rx_framing_error = 1'b1;
    @(negedge clk);
    rx_framing_error = 1'b0;
    expect_response(6, 8'h1f, 8'h03);

    // 半包超过 inter-byte timeout 后不能释放 CPU。
    send_magic();
    send_byte(8'h01);
    expect_response(8, 8'h1f, 8'h05);

    // CRC 错误会清理已写入 BRAM，并允许同一轮直接重传。
    send_packet(8'h40, 1'b1);
    expect_response(10, 8'h1f, 8'h04);
    for (i = 0; i < (1 << ADDR_WIDTH); i = i + 1) begin
        if (mem[i] !== 32'h0000_0000) begin
            $display("FAIL: 失败数据包残留了 mem[%0d]=%08x", i, mem[i]);
            $finish;
        end
    end

    send_packet(8'ha0, 1'b0);
    expect_response(12, 8'h79, 8'h00);
    wait (cpu_release === 1'b1);

    if (mem[0] !== 32'ha3a2_a1a0 || mem[1] !== 32'ha7a6_a5a4) begin
        $display("FAIL: payload byte 没有写入正确的 BRAM byte lane");
        $finish;
    end
    if (last_error !== 8'h00) begin
        $display("FAIL: 成功数据包没有清除 last_error");
        $finish;
    end

    // RESET 后用 LOAD_IMAGE 同时装载 BRAM 和 SDRAM，再次释放 CPU。
    @(negedge clk);
    reset = 1'b1;
    repeat (2) @(negedge clk);
    reset = 1'b0;
    expect_response(14, 8'h52, 8'h00);
    send_image_packet();
    expect_response(16, 8'h79, 8'h00);
    wait (cpu_release === 1'b1);

    if (mem[0] !== 32'hc3c2_c1c0 || mem[1] !== 32'hc7c6_c5c4) begin
        $display("FAIL: LOAD_IMAGE 的 BRAM payload 错误");
        $finish;
    end
    if (sdram_mem[0] !== 32'he3e2_e1e0 || sdram_mem[1] !== 32'he7e6_e5e4) begin
        $display("FAIL: LOAD_IMAGE 的 SDRAM payload 错误：%08x %08x",
                 sdram_mem[0], sdram_mem[1]);
        $finish;
    end

    $display("PASS: bootloader v1 兼容、LOAD_IMAGE 双段装载、错误恢复与 CRC32");
    $finish;
end

endmodule
