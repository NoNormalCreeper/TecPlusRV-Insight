// MiniSoC bootloader 串行波形级回归。
// 先验证坏 CRC 不释放 CPU且无需 RESET 可重传，再验证 RESET 后下载第二份程序。
`timescale 1ns/1ps

module tb_minisoc_bootloader #(
    parameter integer CPU_IMPL = 0,
    parameter FIRMWARE_MEM_FILE = "firmware/build/firmware.mem",
    parameter integer IMAGE_SDRAM_WORDS = 68,
    parameter integer TIMEOUT_CYCLES = 300000
);

localparam integer CLK_FREQ = 1000000;
localparam integer UART_BAUD = 100000;
localparam integer UART_CLKS_PER_BIT = CLK_FREQ / UART_BAUD;
localparam integer UART_BIT_NS = UART_CLKS_PER_BIT * 10;
localparam integer PAYLOAD_LEN = 20;

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

integer wait_cycles;
integer boot_sdram_req_count;
reg [7:0] response_0;
reg [7:0] response_1;

tecplus_minisoc_top #(
    .CLK_FREQ(CLK_FREQ),
    .UART_BAUD(UART_BAUD),
    .CPU_IMPL(CPU_IMPL),
    .BRAM_ADDR_WIDTH(14),
    .BOOTLOADER_ENABLE(1),
    .BOOT_TIMEOUT_CYCLES(2000),
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

function [31:0] payload_word;
    input integer word_index;
    input [7:0] exit_code;
    begin
        case (word_index)
            0: payload_word = 32'h1000_02b7; // lui  t0, 0x10000
            1: payload_word = 32'h0302_8293; // addi t0, t0, 0x30
            2: payload_word = {12'h000, 5'd0, 3'b000, 5'd6, 7'b0010011} |
                              ({24'h000000, exit_code} << 20); // addi t1, zero, exit_code
            3: payload_word = 32'h0062_a023; // sw   t1, 0(t0)
            default: payload_word = 32'h0000_006f; // jal zero, 0
        endcase
    end
endfunction

function [7:0] payload_byte;
    input integer byte_index;
    input [7:0] exit_code;
    reg [31:0] word_value;
    begin
        word_value = payload_word(byte_index / 4, exit_code);
        payload_byte = (word_value >> ((byte_index % 4) * 8)) & 8'hff;
    end
endfunction

task drive_uart_byte;
    input [7:0] value;
    integer bit_index;
    begin
        @(negedge clk);
        uart_rxd = 1'b0;
        repeat (UART_CLKS_PER_BIT) @(posedge clk);
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            @(negedge clk);
            uart_rxd = value[bit_index];
            repeat (UART_CLKS_PER_BIT) @(posedge clk);
        end
        @(negedge clk);
        uart_rxd = 1'b1;
        repeat (UART_CLKS_PER_BIT) @(posedge clk);
    end
endtask

task send_image_packet;
    input [7:0] exit_code;
    reg [31:0] crc;
    reg [31:0] final_crc;
    reg [7:0] value;
    integer byte_index;
    begin
        drive_uart_byte(8'h1e);
        drive_uart_byte(8'hbb);
        drive_uart_byte(8'hda);
        drive_uart_byte(8'hba);
        crc = 32'hffff_ffff;

        drive_uart_byte(8'h01); crc = crc32_byte(crc, 8'h01);
        drive_uart_byte(8'h02); crc = crc32_byte(crc, 8'h02);
        drive_uart_byte(PAYLOAD_LEN[7:0]); crc = crc32_byte(crc, PAYLOAD_LEN[7:0]);
        drive_uart_byte(8'h00); crc = crc32_byte(crc, 8'h00);
        drive_uart_byte(8'h00); crc = crc32_byte(crc, 8'h00);
        drive_uart_byte(8'h00); crc = crc32_byte(crc, 8'h00);
        // SDRAM 地址 0x81000000，长度由参数决定；68 words 可覆盖 refresh
        // 与 bootloader ready-first 请求相遇的边界。
        drive_uart_byte(8'h00); crc = crc32_byte(crc, 8'h00);
        drive_uart_byte(8'h00); crc = crc32_byte(crc, 8'h00);
        drive_uart_byte(8'h00); crc = crc32_byte(crc, 8'h00);
        drive_uart_byte(8'h81); crc = crc32_byte(crc, 8'h81);
        drive_uart_byte((IMAGE_SDRAM_WORDS * 4) & 8'hff);
        crc = crc32_byte(crc, (IMAGE_SDRAM_WORDS * 4) & 8'hff);
        drive_uart_byte(((IMAGE_SDRAM_WORDS * 4) >> 8) & 8'hff);
        crc = crc32_byte(crc, ((IMAGE_SDRAM_WORDS * 4) >> 8) & 8'hff);
        drive_uart_byte(((IMAGE_SDRAM_WORDS * 4) >> 16) & 8'hff);
        crc = crc32_byte(crc, ((IMAGE_SDRAM_WORDS * 4) >> 16) & 8'hff);
        drive_uart_byte(((IMAGE_SDRAM_WORDS * 4) >> 24) & 8'hff);
        crc = crc32_byte(crc, ((IMAGE_SDRAM_WORDS * 4) >> 24) & 8'hff);

        for (byte_index = 0; byte_index < PAYLOAD_LEN; byte_index = byte_index + 1) begin
            value = payload_byte(byte_index, exit_code);
            drive_uart_byte(value);
            crc = crc32_byte(crc, value);
        end
        for (byte_index = 0; byte_index < IMAGE_SDRAM_WORDS * 4; byte_index = byte_index + 1) begin
            value = 8'he0 + byte_index;
            drive_uart_byte(value);
            crc = crc32_byte(crc, value);
        end

        final_crc = ~crc;
        drive_uart_byte(final_crc[7:0]);
        drive_uart_byte(final_crc[15:8]);
        drive_uart_byte(final_crc[23:16]);
        drive_uart_byte(final_crc[31:24]);
    end
endtask

task receive_uart_byte;
    output [7:0] value;
    integer bit_index;
    begin
        @(negedge uart_txd);
        #(UART_BIT_NS + UART_BIT_NS / 2);
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            value[bit_index] = uart_txd;
            #(UART_BIT_NS);
        end
    end
endtask

task receive_response;
    input [7:0] expected_0;
    input [7:0] expected_1;
    begin
        receive_uart_byte(response_0);
        receive_uart_byte(response_1);
        if (response_0 !== expected_0 || response_1 !== expected_1) begin
            $display("FAIL: boot response=%02x %02x，期望=%02x %02x",
                     response_0, response_1, expected_0, expected_1);
            $finish;
        end
    end
endtask

task send_packet;
    input [7:0] exit_code;
    input       corrupt_crc;
    reg [31:0] crc;
    reg [31:0] final_crc;
    reg [7:0] value;
    integer byte_index;
    begin
        drive_uart_byte(8'h1e);
        drive_uart_byte(8'hbb);
        drive_uart_byte(8'hda);
        drive_uart_byte(8'hba);

        crc = 32'hffff_ffff;
        drive_uart_byte(8'h01);
        crc = crc32_byte(crc, 8'h01);
        drive_uart_byte(8'h01);
        crc = crc32_byte(crc, 8'h01);

        drive_uart_byte(PAYLOAD_LEN[7:0]);
        crc = crc32_byte(crc, PAYLOAD_LEN[7:0]);
        drive_uart_byte(8'h00);
        crc = crc32_byte(crc, 8'h00);
        drive_uart_byte(8'h00);
        crc = crc32_byte(crc, 8'h00);
        drive_uart_byte(8'h00);
        crc = crc32_byte(crc, 8'h00);

        for (byte_index = 0; byte_index < PAYLOAD_LEN; byte_index = byte_index + 1) begin
            value = payload_byte(byte_index, exit_code);
            drive_uart_byte(value);
            crc = crc32_byte(crc, value);
        end

        final_crc = ~crc;
        if (corrupt_crc)
            final_crc = final_crc ^ 32'h0000_0001;
        drive_uart_byte(final_crc[7:0]);
        drive_uart_byte(final_crc[15:8]);
        drive_uart_byte(final_crc[23:16]);
        drive_uart_byte(final_crc[31:24]);
    end
endtask

task wait_exit_code;
    input [31:0] expected_code;
    begin
        wait_cycles = 0;
        while (!dut.test_exited && wait_cycles < TIMEOUT_CYCLES) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end
        if (!dut.test_exited) begin
            $display("TIMEOUT: 下载后的 CPU payload 没有到达 test_exit");
            $finish;
        end
        if (dut.test_exit_code !== expected_code) begin
            $display("FAIL: test_exit=%08x，期望=%08x", dut.test_exit_code, expected_code);
            $finish;
        end
    end
endtask

initial begin
    clk = 1'b0;
    reset = 1'b0;
    key = 4'b1111;
    uart_rxd = 1'b1;
    boot_sdram_req_count = 0;

    $dumpfile("sim/build/tb_minisoc_bootloader.vcd");
    $dumpvars(0, tb_minisoc_bootloader);

    repeat (5) @(posedge clk);
    reset = 1'b1;

    receive_response(8'h52, 8'h00);
    if (dut.boot_cpu_release) begin
        $display("FAIL: 合法 payload 到达前 CPU 已被释放");
        $finish;
    end

    // 坏包必须保持 CPU reset；NACK 后不用按 RESET 就能重传。
    send_packet(8'h7f, 1'b1);
    receive_response(8'h1f, 8'h04);
    if (dut.boot_cpu_release || dut.test_exited) begin
        $display("FAIL: CRC 错误时 CPU 仍开始执行");
        $finish;
    end

    send_packet(8'h01, 1'b0);
    receive_response(8'h79, 8'h00);
    wait_exit_code(32'h0000_0001);

    // 板级 RESET 不重烧 bitstream：loader 重新清 BRAM并接受第二份程序。
    reset = 1'b0;
    repeat (5) @(posedge clk);
    reset = 1'b1;
    receive_response(8'h52, 8'h00);
    if (dut.boot_cpu_release || dut.test_exited) begin
        $display("FAIL: RESET 后没有回到 bootloader 等待状态");
        $finish;
    end

    send_image_packet(8'h02);
    receive_response(8'h79, 8'h00);
    wait_exit_code(32'h0000_0002);

    if (boot_sdram_req_count != IMAGE_SDRAM_WORDS ||
        model_write_command_count != IMAGE_SDRAM_WORDS * 2) begin
        $display("FAIL: LOAD_IMAGE 没有形成 %0d 个 32-bit / %0d 个 x16 SDRAM write：req=%0d cmd=%0d",
                 IMAGE_SDRAM_WORDS, IMAGE_SDRAM_WORDS * 2,
                 boot_sdram_req_count, model_write_command_count);
        $finish;
    end

    $display("PASS: bootloader CPU=%0d 支持 v1 重传与 LOAD_IMAGE 真实 SDRAM 写入", CPU_IMPL);
    $finish;
end

initial begin
    repeat (TIMEOUT_CYCLES) @(posedge clk);
    $display("TIMEOUT: bootloader 长 LOAD_IMAGE 未完成 req=%0d ready=%b valid=%b ctrl_state=%0d",
             boot_sdram_req_count, dut.sdram_req_ready, dut.boot_sdram_req_valid,
             dut.u_sdram.dbg_state);
    $finish;
end

always @(posedge clk) begin
    if (dut.boot_active && dut.boot_sdram_req_valid && dut.sdram_req_ready) begin
        if (dut.boot_sdram_req_addr !== 32'h8100_0000 + boot_sdram_req_count * 4) begin
            $display("FAIL: bootloader SDRAM 地址序列错误：%08x", dut.boot_sdram_req_addr);
            $finish;
        end
        boot_sdram_req_count = boot_sdram_req_count + 1;
    end
end

endmodule
