// Bootloader board-test firmware 端到端仿真：CPU 全量读回预装的 BTV1 SDRAM asset。
`timescale 1ns/1ps

module tb_boot_image_verify #(
    parameter integer CPU_IMPL = 0,
    parameter FIRMWARE_MEM_FILE = "firmware/build/boot_image_verify.mem",
    parameter ASSET_MEM_FILE = "sim/build/boot_image_test.mem",
    parameter integer ASSET_WORD_COUNT = 68
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

reg [31:0] asset_words [0:1023];
integer asset_word_count;
integer i;
integer cycles;
integer uart_write_count;

tecplus_minisoc_top #(
    .CLK_FREQ(1000000),
    .UART_BAUD(100000),
    .CPU_IMPL(CPU_IMPL),
    .BRAM_ADDR_WIDTH(14),
    .BRAM_INIT_FILE(FIRMWARE_MEM_FILE)
) dut (
    .clk(clk), .reset(reset), .key(key), .led(led),
    .uart_rxd(uart_rxd), .uart_txd(uart_txd), .tl(tl), .spk(spk),
    .sh_clk(sh_clk), .sh_cke(sh_cke), .sh_ncs(sh_ncs), .sh_nwe(sh_nwe),
    .sh_ncas(sh_ncas), .sh_nras(sh_nras), .sh_dqm(sh_dqm),
    .sh_ba(sh_ba), .sh_a(sh_a), .sh_db(sh_db)
);

sdram_x16_model model (
    .clk(clk), .reset(!reset), .cke(sh_cke), .cs_n(sh_ncs),
    .ras_n(sh_nras), .cas_n(sh_ncas), .we_n(sh_nwe), .dqm(sh_dqm),
    .ba(sh_ba), .addr(sh_a), .dq(sh_db),
    .read_command_count(model_read_command_count),
    .write_command_count(model_write_command_count)
);

function [15:0] model_key;
    input [31:0] byte_addr;
    reg [4:0] row_key;
    begin
        row_key = byte_addr[16:12] ^ {4'b0000, byte_addr[24]};
        model_key = {row_key, byte_addr[11:10], byte_addr[9:1]};
    end
endfunction

always #5 clk = ~clk;

always @(posedge clk) begin
    if (reset && dut.uart_fire)
        uart_write_count = uart_write_count + 1;
end

initial begin
    clk = 1'b0;
    reset = 1'b0;
    key = 4'b1111;
    uart_rxd = 1'b1;
    cycles = 0;
    uart_write_count = 0;

    $readmemh(ASSET_MEM_FILE, asset_words, 0, ASSET_WORD_COUNT - 1);
    #2;
    asset_word_count = asset_words[2] + 4;
    if (asset_word_count != ASSET_WORD_COUNT) begin
        $display("FAIL: BTV1 word count=%0d，testbench 参数=%0d",
                 asset_word_count, ASSET_WORD_COUNT);
        $finish;
    end
    for (i = 0; i < asset_word_count; i = i + 1) begin
        model.mem[model_key(32'h8100_0000 + i * 4)] = asset_words[i][15:0];
        model.mem[model_key(32'h8100_0002 + i * 4)] = asset_words[i][31:16];
    end

    repeat (5) @(posedge clk);
    reset = 1'b1;

    while (cycles < 2000000 && !dut.test_exited) begin
        @(posedge clk);
        cycles = cycles + 1;
    end

    if (!dut.test_exited || dut.test_exit_code !== 32'h0000_0001 ||
        led !== 4'h5 || uart_write_count < 10 ||
        model_read_command_count < asset_word_count) begin
        $display("TIMEOUT: boot image verify 证据不足 exit=%b code=%08x led=%x uart=%0d reads=%0d/%0d",
                 dut.test_exited, dut.test_exit_code, led, uart_write_count,
                 model_read_command_count, asset_word_count);
        $finish;
    end

    $display("PASS: boot image verify CPU=%0d 全量读回 %0d 个 BTV1 word",
             CPU_IMPL, asset_word_count);
    $finish;
end

endmodule
