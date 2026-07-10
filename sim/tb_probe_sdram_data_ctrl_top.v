// probe_sdram_data_ctrl_top 的集成仿真。
// 这里沿用 tb_sdram_data_ctrl 的简化 SDRAM 模型，并在 reporter -> uart_tx 的握手点检查 PASS 文本。
`timescale 1ns/1ps

module tb_probe_sdram_data_ctrl_top;

reg clk;
reg reset;
reg [3:0] key;
reg uart_rxd;

wire uart_txd;
wire [3:0] led;
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

reg [15:0] dq_drive;
reg        dq_drive_en;

reg [15:0] mem [0:65535];

integer i;
integer init_stage;
integer read_wait;
integer uart_byte_index;
reg        read_pending;
reg [15:0] read_data_latch;
reg [1:0]  open_ba;
reg [12:0] open_row;
reg        row_open;
reg        expect_is_write;
integer    expect_phase;
reg [1:0]  expect_bank;
reg [12:0] expect_row;
reg [8:0]  expect_col_lo;
reg [8:0]  expect_col_hi;
reg        misaligned_inflight;

assign sh_db = dq_drive_en ? dq_drive : 16'hzzzz;

probe_sdram_data_ctrl_top #(
    .CLK_FREQ(1000000),
    .UART_BAUD(1000000),
    .CTRL_PWRUP_WAIT_CYCLES(4),
    .CTRL_TRP_CYCLES(2),
    .CTRL_TRFC_CYCLES(3),
    .CTRL_TMRD_CYCLES(2),
    .CTRL_TRCD_CYCLES(2),
    .CTRL_TWR_CYCLES(2),
    .CTRL_CAS_LATENCY_CYCLES(2),
    .CTRL_REFI_CYCLES(20),
    .CTRL_REFRESH_DEFER_CYCLES(24),
    .RUNNER_WAIT_TIMEOUT_CYCLES(300),
    .RUNNER_PRESSURE_TIMEOUT_CYCLES(300),
    .RUNNER_LOCAL_RESET_HOLD_CYCLES(3)
) dut (
    .clk(clk),
    .reset(reset),
    .key(key),
    .uart_rxd(uart_rxd),
    .uart_txd(uart_txd),
    .led(led),
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

always #5 clk = ~clk;

function [15:0] mk_addr_key;
    input [12:0] row;
    input [1:0] ba;
    input [8:0] col;
    reg [4:0] row_key;
    begin
        row_key = row[4:0] ^ {4'b0000, row[12]};
        mk_addr_key = {row_key, ba, col};
    end
endfunction

function [7:0] hex_digit;
    input [3:0] value;
    begin
        if (value < 4'd10) begin
            hex_digit = "0" + value;
        end else begin
            hex_digit = "a" + (value - 4'd10);
        end
    end
endfunction

function [7:0] info_hex;
    input [31:0] info;
    input integer nibble_index;
    begin
        case (nibble_index)
            0: info_hex = hex_digit(info[31:28]);
            1: info_hex = hex_digit(info[27:24]);
            2: info_hex = hex_digit(info[23:20]);
            3: info_hex = hex_digit(info[19:16]);
            4: info_hex = hex_digit(info[15:12]);
            5: info_hex = hex_digit(info[11:8]);
            6: info_hex = hex_digit(info[7:4]);
            default: info_hex = hex_digit(info[3:0]);
        endcase
    end
endfunction

function [7:0] expected_pass_byte;
    input integer index;
    input [31:0] info;
    begin
        case (index)
            0: expected_pass_byte = "P";
            1: expected_pass_byte = "A";
            2: expected_pass_byte = "S";
            3: expected_pass_byte = "S";
            4: expected_pass_byte = " ";
            5: expected_pass_byte = "c";
            6: expected_pass_byte = "=";
            7: expected_pass_byte = "0";
            8: expected_pass_byte = "7";
            9: expected_pass_byte = " ";
            10: expected_pass_byte = "i";
            11: expected_pass_byte = "=";
            12: expected_pass_byte = info_hex(info, 0);
            13: expected_pass_byte = info_hex(info, 1);
            14: expected_pass_byte = info_hex(info, 2);
            15: expected_pass_byte = info_hex(info, 3);
            16: expected_pass_byte = info_hex(info, 4);
            17: expected_pass_byte = info_hex(info, 5);
            18: expected_pass_byte = info_hex(info, 6);
            19: expected_pass_byte = info_hex(info, 7);
            20: expected_pass_byte = 8'h0d;
            default: expected_pass_byte = 8'h0a;
        endcase
    end
endfunction

initial begin
    clk = 1'b0;
    reset = 1'b0;
    key = 4'hf;
    uart_rxd = 1'b1;
    dq_drive = 16'h0000;
    dq_drive_en = 1'b0;
    init_stage = 0;
    read_wait = 0;
    uart_byte_index = 0;
    read_pending = 1'b0;
    read_data_latch = 16'd0;
    open_ba = 2'b00;
    open_row = 13'd0;
    row_open = 1'b0;
    expect_is_write = 1'b0;
    expect_phase = 0;
    expect_bank = 2'b00;
    expect_row = 13'd0;
    expect_col_lo = 9'd0;
    expect_col_hi = 9'd0;
    misaligned_inflight = 1'b0;

    for (i = 0; i < 65536; i = i + 1) begin
        mem[i] = 16'h0000;
    end

    $dumpfile("sim/build/tb_probe_sdram_data_ctrl_top.vcd");
    $dumpvars(0, tb_probe_sdram_data_ctrl_top);

    repeat (4) @(posedge clk);
    reset = 1'b1;

    repeat (30000) @(posedge clk);
    $display("FAIL: probe_sdram_data_ctrl_top 在超时前未完成");
    $finish;
end

always @(posedge clk) begin
    if (reset && dut.runner.report_valid && dut.runner.report_fail) begin
        $display("FAIL: runner reported failure case=%02x step=%02x err=%02x info=%08x exp=%08x act=%08x",
            dut.runner.report_case_id,
            dut.runner.report_step_id,
            dut.runner.report_error_code,
            dut.runner.report_info,
            dut.runner.report_expected,
            dut.runner.report_actual);
        $finish;
    end

    if (reset && dut.reporter_valid && dut.uart_ready) begin
        if (dut.reporter_data !== expected_pass_byte(uart_byte_index, dut.runner.report_info)) begin
            $display("FAIL: PASS reporter byte %0d expected=0x%02x actual=0x%02x",
                uart_byte_index,
                expected_pass_byte(uart_byte_index, dut.runner.report_info),
                dut.reporter_data);
            $finish;
        end

        if (uart_byte_index == 21) begin
            if (dut.runner.report_case_id !== 8'h07) begin
                $display("FAIL: PASS case id mismatch, got=%02x", dut.runner.report_case_id);
                $finish;
            end
            if (dut.runner.report_fail !== 1'b0) begin
                $display("FAIL: probe should finish with PASS, but report_fail=1");
                $finish;
            end
            if (led !== 4'b1000) begin
                $display("FAIL: PASS 后 LED 不是 1000，而是 %b", led);
                $finish;
            end
            $display("PASS: probe_sdram_data_ctrl_top M2a 板级自检链路正常");
            $finish;
        end

        uart_byte_index = uart_byte_index + 1;
    end
end

always @(posedge clk) begin
    #1;
    if (dut.ctrl_reset) begin
        row_open <= 1'b0;
        open_ba <= 2'b00;
        open_row <= 13'd0;
        read_wait <= 0;
        read_pending <= 1'b0;
        dq_drive <= 16'h0000;
        dq_drive_en <= 1'b0;
        expect_is_write <= 1'b0;
        expect_phase <= 0;
        expect_bank <= 2'b00;
        expect_row <= 13'd0;
        expect_col_lo <= 9'd0;
        expect_col_hi <= 9'd0;
        misaligned_inflight <= 1'b0;
        init_stage <= 0;
    end else begin
        if (read_pending) begin
            if (read_wait == 0) begin
                dq_drive <= read_data_latch;
                dq_drive_en <= 1'b1;
                read_pending <= 1'b0;
            end else begin
                read_wait <= read_wait - 1;
            end
        end else begin
            dq_drive_en <= 1'b0;
        end

        if (dut.req_valid && dut.req_ready) begin
            if (dut.req_addr[1:0] == 2'b00) begin
                expect_is_write <= dut.req_we;
                expect_phase <= 1;
                expect_bank <= dut.req_addr[11:10];
                expect_row <= dut.req_addr[24:12];
                expect_col_lo <= dut.req_addr[9:1];
                expect_col_hi <= dut.req_addr[9:1] + 9'd1;
                misaligned_inflight <= 1'b0;
            end else begin
                expect_phase <= 0;
                misaligned_inflight <= 1'b1;
            end
        end

        if (dut.resp_valid) begin
            misaligned_inflight <= 1'b0;
        end

        if (misaligned_inflight &&
            !sh_ncs &&
            ((!sh_nras && sh_ncas && sh_nwe) ||
             (sh_nras && !sh_ncas && !sh_nwe) ||
             (sh_nras && !sh_ncas && sh_nwe) ||
             (!sh_nras && sh_ncas && !sh_nwe))) begin
            $display("FAIL: misaligned request should not issue SDRAM command");
            $finish;
        end

        // ACTIVE
        if (!sh_ncs && !sh_nras && sh_ncas && sh_nwe) begin
            if (expect_phase == 1) begin
                if (sh_ba !== expect_bank || sh_a !== expect_row) begin
                    $display("FAIL: ACT address mismatch, got bank=%b row=%h exp bank=%b row=%h",
                        sh_ba, sh_a, expect_bank, expect_row);
                    $finish;
                end
                expect_phase <= 2;
            end
            row_open <= 1'b1;
            open_ba <= sh_ba;
            open_row <= sh_a;
        end

        // PRECHARGE
        if (!sh_ncs && !sh_nras && sh_ncas && !sh_nwe) begin
            row_open <= 1'b0;

            if (init_stage < 4) begin
                if (init_stage == 0) begin
                    if (sh_a[10] !== 1'b1) begin
                        $display("FAIL: init PRECHARGE not ALL banks");
                        $finish;
                    end
                    init_stage <= 1;
                end else begin
                    $display("FAIL: unexpected PRECHARGE during init, stage=%0d", init_stage);
                    $finish;
                end
            end
        end

        // AUTO REFRESH
        if (!sh_ncs && !sh_nras && !sh_ncas && sh_nwe) begin
            if (init_stage < 4) begin
                if (init_stage == 1) begin
                    init_stage <= 2;
                end else if (init_stage == 2) begin
                    init_stage <= 3;
                end else begin
                    $display("FAIL: init AUTO REFRESH order wrong, stage=%0d", init_stage);
                    $finish;
                end
            end
        end

        // LOAD MODE
        if (!sh_ncs && !sh_nras && !sh_ncas && !sh_nwe) begin
            if (init_stage < 4) begin
                if (init_stage == 3) begin
                    init_stage <= 4;
                end else begin
                    $display("FAIL: init LOAD MODE order wrong, stage=%0d", init_stage);
                    $finish;
                end
            end
        end

        // WRITE
        if (!sh_ncs && sh_nras && !sh_ncas && !sh_nwe) begin
            if (!row_open) begin
                $display("FAIL: WRITE without open row");
                $finish;
            end
            if (sh_ba !== open_ba) begin
                $display("FAIL: WRITE bank mismatch, got=%b open=%b", sh_ba, open_ba);
                $finish;
            end
            if (expect_phase == 2 || expect_phase == 3) begin
                if (!expect_is_write) begin
                    $display("FAIL: saw WRITE but expected READ command");
                    $finish;
                end
                if (sh_ba !== expect_bank) begin
                    $display("FAIL: WRITE bank mismatch against expected access, got=%b exp=%b",
                        sh_ba, expect_bank);
                    $finish;
                end
                if (expect_phase == 2 && sh_a[8:0] !== expect_col_lo) begin
                    $display("FAIL: low-half WRITE column mismatch, got=%h exp=%h",
                        sh_a[8:0], expect_col_lo);
                    $finish;
                end
                if (expect_phase == 3 && sh_a[8:0] !== expect_col_hi) begin
                    $display("FAIL: high-half WRITE column mismatch, got=%h exp=%h",
                        sh_a[8:0], expect_col_hi);
                    $finish;
                end
                if (expect_phase == 2) expect_phase <= 3;
                else expect_phase <= 0;
            end
            if (dut.dq_oe !== 1'b1) begin
                $display("FAIL: dq_oe not asserted during WRITE");
                $finish;
            end
            if (!sh_dqm[0]) mem[mk_addr_key(open_row, sh_ba, sh_a[8:0])][7:0] <= dut.dq_out[7:0];
            if (!sh_dqm[1]) mem[mk_addr_key(open_row, sh_ba, sh_a[8:0])][15:8] <= dut.dq_out[15:8];
        end

        // READ
        if (!sh_ncs && sh_nras && !sh_ncas && sh_nwe) begin
            if (!row_open) begin
                $display("FAIL: READ without open row");
                $finish;
            end
            if (sh_ba !== open_ba) begin
                $display("FAIL: READ bank mismatch, got=%b open=%b", sh_ba, open_ba);
                $finish;
            end
            if (expect_phase == 2 || expect_phase == 3) begin
                if (expect_is_write) begin
                    $display("FAIL: saw READ but expected WRITE command");
                    $finish;
                end
                if (sh_ba !== expect_bank) begin
                    $display("FAIL: READ bank mismatch against expected access, got=%b exp=%b",
                        sh_ba, expect_bank);
                    $finish;
                end
                if (expect_phase == 2 && sh_a[8:0] !== expect_col_lo) begin
                    $display("FAIL: low-half READ column mismatch, got=%h exp=%h",
                        sh_a[8:0], expect_col_lo);
                    $finish;
                end
                if (expect_phase == 3 && sh_a[8:0] !== expect_col_hi) begin
                    $display("FAIL: high-half READ column mismatch, got=%h exp=%h",
                        sh_a[8:0], expect_col_hi);
                    $finish;
                end
                if (expect_phase == 2) expect_phase <= 3;
                else expect_phase <= 0;
            end
            if (dut.dq_oe !== 1'b0) begin
                $display("FAIL: dq_oe asserted during READ");
                $finish;
            end
            read_data_latch <= mem[mk_addr_key(open_row, sh_ba, sh_a[8:0])];
            read_wait <= 2;
            read_pending <= 1'b1;
        end
    end
end

endmodule
