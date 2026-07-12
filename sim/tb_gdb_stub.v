// DarkRISCV GDB stub 的 CPU + UART 端到端仿真。
`timescale 1ns/1ps

module tb_gdb_stub #(
    parameter integer CPU_IMPL = 1,
    parameter [31:0] CONTINUE_PC = 32'h0000_0000,
    parameter integer EXPLICIT_PC = 1,
    parameter FIRMWARE_MEM_FILE = "firmware/build/firmware.mem"
);

localparam integer UART_CLKS_PER_BIT = 100;
localparam integer UART_BIT_NS = 1000;

reg clk;
reg reset;
reg uart_rxd;
reg [7:0] uart_test_byte;
reg [7:0] tx_buffer [0:511];
reg [7:0] rx_buffer [0:511];
integer rx_length;
integer index;
integer target_tx_count;
integer mcause_word_index;
reg [31:0] stopped_sp;

wire [3:0] led;
wire uart_txd;
wire [11:0] tl;
wire spk;
wire [15:0] sh_db;

tecplus_minisoc_top #(
    .CLK_FREQ(1000000),
    .UART_BAUD(10000),
    .CPU_IMPL(CPU_IMPL),
    .BRAM_ADDR_WIDTH(14),
    .BRAM_INIT_FILE(FIRMWARE_MEM_FILE)
) dut (
    .clk(clk), .reset(reset), .key(4'hf), .led(led),
    .uart_rxd(uart_rxd), .uart_txd(uart_txd), .tl(tl), .spk(spk),
    .vga_r(), .vga_g(), .vga_b(), .vga_hs(), .vga_vs(),
    .vga_mf(), .vga_clr(), .vga_qd(),
    .sh_clk(), .sh_cke(), .sh_ncs(), .sh_nwe(), .sh_ncas(), .sh_nras(),
    .sh_dqm(), .sh_ba(), .sh_a(), .sh_db(sh_db)
);

always #5 clk = ~clk;

always @(posedge clk) begin
    if (!reset)
        target_tx_count <= 0;
    else if (dut.uart_fire)
        target_tx_count <= target_tx_count + 1;
end

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

task send_buffer_packet;
    input integer length;
    integer byte_index;
    reg [7:0] checksum;
    begin
        checksum = 8'h00;
        drive_uart_byte("$");
        for (byte_index = 0; byte_index < length; byte_index = byte_index + 1) begin
            drive_uart_byte(tx_buffer[byte_index]);
            checksum = checksum + tx_buffer[byte_index];
        end
        drive_uart_byte("#");
        drive_uart_byte(checksum[7:4] < 10 ? "0" + checksum[7:4]
                                           : "a" + checksum[7:4] - 10);
        drive_uart_byte(checksum[3:0] < 10 ? "0" + checksum[3:0]
                                           : "a" + checksum[3:0] - 10);
    end
endtask

task send_short_packet;
    input [2047:0] payload;
    input integer length;
    integer byte_index;
    begin
        for (byte_index = 0; byte_index < length; byte_index = byte_index + 1)
            tx_buffer[byte_index] = payload >> ((length - byte_index - 1) * 8);
        send_buffer_packet(length);
    end
endtask

function [7:0] hex_ascii;
    input [3:0] nibble;
    begin
        hex_ascii = nibble < 10 ? "0" + nibble : "a" + nibble - 10;
    end
endfunction

function [3:0] ascii_hex;
    input [7:0] value;
    begin
        ascii_hex = value >= "a" ? value - "a" + 10 : value - "0";
    end
endfunction

task read_u32_le_from_rx;
    input integer offset;
    output [31:0] value;
    integer byte_index;
    reg [7:0] byte_value;
    begin
        value = 32'h0000_0000;
        for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
            byte_value = {ascii_hex(rx_buffer[offset + byte_index * 2]),
                          ascii_hex(rx_buffer[offset + byte_index * 2 + 1])};
            value = value | (byte_value << (byte_index * 8));
        end
    end
endtask

task write_u32_le_to_tx;
    input integer offset;
    input [31:0] value;
    integer byte_index;
    reg [7:0] byte_value;
    begin
        for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
            byte_value = value >> (byte_index * 8);
            tx_buffer[offset + byte_index * 2] = hex_ascii(byte_value[7:4]);
            tx_buffer[offset + byte_index * 2 + 1] = hex_ascii(byte_value[3:0]);
        end
    end
endtask

task write_u32_be_hex_to_tx;
    input integer offset;
    input [31:0] value;
    integer nibble_index;
    begin
        for (nibble_index = 0; nibble_index < 8; nibble_index = nibble_index + 1)
            tx_buffer[offset + nibble_index] =
                hex_ascii(value >> ((7 - nibble_index) * 4));
    end
endtask

task receive_reply_mode;
    input integer expect_ack_byte;
    reg [7:0] value;
    reg [7:0] checksum;
    reg [7:0] received_checksum;
    integer high;
    integer low;
    begin
        receive_uart_byte(value);
        if (expect_ack_byte != 0) begin
            if (value !== "+") begin
                $display("FAIL: GDB request 未收到 ACK，实际=%02x", value);
                $finish;
            end
            receive_uart_byte(value);
        end
        if (value !== "$") begin
            $display("FAIL: GDB reply 缺少起始符，实际=%02x", value);
            $finish;
        end

        checksum = 8'h00;
        rx_length = 0;
        receive_uart_byte(value);
        while (value != "#") begin
            if (rx_length >= 512) begin
                $display("FAIL: GDB reply 超过 testbench buffer");
                $finish;
            end
            rx_buffer[rx_length] = value;
            rx_length = rx_length + 1;
            checksum = checksum + value;
            receive_uart_byte(value);
        end

        receive_uart_byte(value);
        high = value >= "a" ? value - "a" + 10 : value - "0";
        receive_uart_byte(value);
        low = value >= "a" ? value - "a" + 10 : value - "0";
        received_checksum = (high << 4) | low;
        if (received_checksum !== checksum) begin
            $display("FAIL: GDB reply checksum 错误");
            $finish;
        end
    end
endtask

task receive_reply;
    begin
        receive_reply_mode(1);
    end
endtask

task assert_text_buffer;
    input [255:0] expected;
    input integer expected_length;
    integer byte_index;
    reg [7:0] expected_byte;
    begin
        if (rx_length != expected_length) begin
            $display("FAIL: GDB reply 长度=%0d，期望=%0d", rx_length, expected_length);
            $finish;
        end
        for (byte_index = 0; byte_index < expected_length; byte_index = byte_index + 1) begin
            expected_byte = expected >> ((expected_length - byte_index - 1) * 8);
            if (rx_buffer[byte_index] !== expected_byte) begin
                $display("FAIL: GDB reply byte[%0d]=%02x，期望=%02x",
                         byte_index, rx_buffer[byte_index], expected_byte);
                $finish;
            end
        end
    end
endtask

task expect_text_reply;
    input [255:0] expected;
    input integer expected_length;
    begin
        receive_reply;
        assert_text_buffer(expected, expected_length);
    end
endtask

task expect_ack;
    reg [7:0] value;
    begin
        receive_uart_byte(value);
        if (value !== "+") begin
            $display("FAIL: continue 未收到 ACK，实际=%02x", value);
            $finish;
        end
    end
endtask

initial begin
    clk = 1'b0;
    reset = 1'b0;
    uart_rxd = 1'b1;
    target_tx_count = 0;
    repeat (5) @(posedge clk);
    reset = 1'b1;

    // 等待 cooperative ebreak 已经进入公共 trap 路径和 stub loop。
    wait (dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MCAUSE == 32'h0000_0003);
    repeat (200) @(posedge clk);

    send_short_packet(
        "qSupported:multiprocess+;swbreak+;hwbreak+;qRelocInsn+;fork-events+;vfork-events+;exec-events+;vContSupported+;QThreadEvents+;no-resumed+;memory-tagging+;xmlRegisters=i386",
        171);
    expect_text_reply("PacketSize=200", 14);

    // Host NACK 必须让 target 重发上一 reply，不能附加 request ACK。
    drive_uart_byte("-");
    receive_reply_mode(0);
    assert_text_buffer("PacketSize=200", 14);

    // checksum 错误只返回 NACK，随后合法 packet 必须能够重新同步。
    drive_uart_byte("$");
    drive_uart_byte("?");
    drive_uart_byte("#");
    drive_uart_byte("0");
    drive_uart_byte("0");
    receive_uart_byte(uart_test_byte);
    if (uart_test_byte !== "-") begin
        $display("FAIL: checksum 错误未收到 NACK，实际=%02x", uart_test_byte);
        $finish;
    end
    send_short_packet("?", 1);
    expect_text_reply("S05", 3);

    send_short_packet("vMustReplyEmpty", 15);
    expect_text_reply("", 0);

    send_short_packet("Hg0", 3);
    expect_text_reply("OK", 2);
    send_short_packet("Hc-1", 4);
    expect_text_reply("OK", 2);
    send_short_packet("qAttached", 9);
    expect_text_reply("1", 1);
    send_short_packet("qTStatus", 8);
    expect_text_reply("", 0);
    send_short_packet("qfThreadInfo", 12);
    expect_text_reply("", 0);

    send_short_packet("?", 1);
    expect_text_reply("S05", 3);

    send_short_packet("g", 1);
    receive_reply;
    if (rx_length != 264) begin
        $display("FAIL: g reply 长度=%0d，期望=264", rx_length);
        $finish;
    end
    for (index = 0; index < 8; index = index + 1) begin
        if (rx_buffer[index] !== "0") begin
            $display("FAIL: g reply 中 x0 不是 0");
            $finish;
        end
    end
    read_u32_le_from_rx(16, stopped_sp);
    mcause_word_index = (stopped_sp - 8) >> 2;

    // 保留完整 context，只通过 G 修改 a0，确保后续 continue 仍可恢复原栈。
    tx_buffer[0] = "G";
    for (index = 0; index < 264; index = index + 1)
        tx_buffer[index + 1] = rx_buffer[index];
    for (index = 1; index <= 8; index = index + 1)
        tx_buffer[index] = "f";
    tx_buffer[81] = "3";
    tx_buffer[82] = "4";
    tx_buffer[83] = "1";
    tx_buffer[84] = "2";
    tx_buffer[85] = "0";
    tx_buffer[86] = "0";
    tx_buffer[87] = "0";
    tx_buffer[88] = "0";
    if (EXPLICIT_PC == 1)
        write_u32_le_to_tx(257, CONTINUE_PC);
    send_buffer_packet(265);
    expect_text_reply("OK", 2);

    send_short_packet("g", 1);
    receive_reply;
    if (rx_length != 264) begin
        $display("FAIL: G 后的 g reply 长度错误");
        $finish;
    end
    if (rx_buffer[80] !== "3" || rx_buffer[81] !== "4" ||
        rx_buffer[82] !== "1" || rx_buffer[83] !== "2" ||
        rx_buffer[84] !== "0" || rx_buffer[85] !== "0" ||
        rx_buffer[86] !== "0" || rx_buffer[87] !== "0") begin
        $display("FAIL: G 未写入 a0=0x00001234");
        $finish;
    end
    for (index = 0; index < 8; index = index + 1) begin
        if (rx_buffer[index] !== "0") begin
            $display("FAIL: G 写入 x0 后未保持为 0");
            $finish;
        end
    end
    if (EXPLICIT_PC == 1) begin
        for (index = 0; index < 8; index = index + 1) begin
            if (rx_buffer[256 + index] !== tx_buffer[257 + index]) begin
                $display("FAIL: G 未写入 PC=%08x", CONTINUE_PC);
                $finish;
            end
        end
    end

    // 直接改 canonical frame 的 mcause，但 stop reply 仍走真实 UART/RSP 路径。
    dut.u_bram.mem[mcause_word_index] = 32'h0000_0002;
    repeat (2) @(posedge clk);
    send_short_packet("?", 1);
    expect_text_reply("S04", 3);
    dut.u_bram.mem[mcause_word_index] = 32'h0000_0004;
    repeat (2) @(posedge clk);
    send_short_packet("?", 1);
    expect_text_reply("S0b", 3);
    dut.u_bram.mem[mcause_word_index] = 32'h0000_0003;
    repeat (2) @(posedge clk);
    send_short_packet("?", 1);
    expect_text_reply("S05", 3);

    send_short_packet("M00003000,4:78563412", 20);
    expect_text_reply("OK", 2);
    send_short_packet("m00003000,4", 11);
    expect_text_reply("78563412", 8);

    send_short_packet("M00003001,5:1122334455", 22);
    expect_text_reply("OK", 2);
    send_short_packet("m00003001,5", 11);
    expect_text_reply("1122334455", 10);

    // 非法 hex 必须在任何 byte write 前整体拒绝。
    send_short_packet("M00003008,4:78563412", 20);
    expect_text_reply("OK", 2);
    send_short_packet("M00003008,4:12xz5678", 20);
    expect_text_reply("E01", 3);
    send_short_packet("m00003008,4", 11);
    expect_text_reply("78563412", 8);

    // testbench 不建 SDRAM read model，但 write transaction 必须走完允许窗口。
    send_short_packet("M80000001,5:1122334455", 22);
    expect_text_reply("OK", 2);

    send_short_packet("m10000010,1", 11);
    expect_text_reply("E01", 3);
    send_short_packet("m0000ffff,2", 11);
    expect_text_reply("E01", 3);
    send_short_packet("mfffffffe,4", 11);
    expect_text_reply("E01", 3);
    send_short_packet("c3", 2);
    expect_text_reply("E01", 3);

    if (EXPLICIT_PC == 2) begin
        tx_buffer[0] = "c";
        write_u32_be_hex_to_tx(1, CONTINUE_PC);
        send_buffer_packet(9);
    end else begin
        send_short_packet("c", 1);
    end
    expect_ack;
    if (EXPLICIT_PC == 0) begin
        // continue 后第二个 ebreak 必须由 target 主动上报，不能等 host 再发 ?。
        receive_reply_mode(0);
        assert_text_buffer("S05", 3);
        drive_uart_byte("+");
        send_short_packet("c", 1);
        expect_ack;
    end
    wait (dut.test_exited);
    if (EXPLICIT_PC != 0 && dut.test_exit_code !== 32'h0000_0001) begin
        $display("FAIL: continue 后 test_exit=%08x", dut.test_exit_code);
        $finish;
    end
    if (EXPLICIT_PC == 0 && dut.test_exit_code !== 32'h0000_0002) begin
        $display("FAIL: cooperative ebreak 后 test_exit=%08x", dut.test_exit_code);
        $finish;
    end

    $display("PASS: DarkRISCV GDB stop/register/memory/continue");
    $finish;
end

initial begin
    repeat (3000000) @(posedge clk);
    $display("TIMEOUT: GDB stub 未完成端到端测试，target_tx_count=%0d rx_length=%0d pc=%08x mepc=%08x mcause=%08x mem_valid=%0d mem_addr=%08x pending=%0d mem_ready=%0d",
             target_tx_count, rx_length,
             dut.u_cpu.g_darkriscv.u_cpu.u_cpu.PC,
             dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MEPC,
             dut.u_cpu.g_darkriscv.u_cpu.u_cpu.MCAUSE,
             dut.mem_valid, dut.mem_addr, dut.pending, dut.mem_ready);
    $finish;
end

endmodule
