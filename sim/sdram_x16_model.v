// MiniSoC 集成仿真使用的最小 x16 SDRAM 行为模型。
// 只覆盖当前 closed-page 控制器需要的命令与 DQM 字节写，不用于替代芯片级时序模型。
module sdram_x16_model #(
    parameter integer CAS_LATENCY_CYCLES = 2
) (
    input         clk,
    input         reset,
    input         cke,
    input         cs_n,
    input         ras_n,
    input         cas_n,
    input         we_n,
    input  [1:0]  dqm,
    input  [1:0]  ba,
    input  [12:0] addr,
    inout  [15:0] dq,
    output reg [31:0] read_command_count,
    output reg [31:0] write_command_count
);

// ponytail: 仅保存 64K halfword，并让高 row 在模型内别名；需要全容量遍历时再换芯片模型。
reg [15:0] mem [0:65535];
reg [1:0]  open_ba;
reg [12:0] open_row;
reg        row_open;
reg [15:0] read_data;
reg        read_pending;
integer    read_wait;
reg [15:0] dq_drive;
reg        dq_drive_en;
integer    i;

assign dq = dq_drive_en ? dq_drive : 16'hzzzz;

function [15:0] mem_key;
    input [12:0] row;
    input [1:0]  bank;
    input [8:0]  col;
    begin
        mem_key = {row[4:0], bank, col};
    end
endfunction

initial begin
    for (i = 0; i < 65536; i = i + 1) begin
        mem[i] = 16'h0000;
    end
end

always @(posedge clk) begin
    #1;
    if (reset) begin
        open_ba <= 2'b00;
        open_row <= 13'd0;
        row_open <= 1'b0;
        read_data <= 16'h0000;
        read_pending <= 1'b0;
        read_wait <= 0;
        dq_drive <= 16'h0000;
        dq_drive_en <= 1'b0;
        read_command_count <= 32'd0;
        write_command_count <= 32'd0;
    end else begin
        if (read_pending) begin
            if (read_wait == 0) begin
                dq_drive <= read_data;
                dq_drive_en <= 1'b1;
                read_pending <= 1'b0;
            end else begin
                read_wait <= read_wait - 1;
            end
        end else begin
            dq_drive_en <= 1'b0;
        end

        if (cke && !cs_n) begin
            // ACTIVE
            if (!ras_n && cas_n && we_n) begin
                open_ba <= ba;
                open_row <= addr;
                row_open <= 1'b1;
            end

            // PRECHARGE
            if (!ras_n && cas_n && !we_n) begin
                row_open <= 1'b0;
            end

            // WRITE
            if (ras_n && !cas_n && !we_n) begin
                if (!row_open || ba != open_ba) begin
                    $display("FAIL: SDRAM model 收到未打开 row/bank 的 WRITE");
                    $finish;
                end
                if (!dqm[0]) mem[mem_key(open_row, ba, addr[8:0])][7:0] <= dq[7:0];
                if (!dqm[1]) mem[mem_key(open_row, ba, addr[8:0])][15:8] <= dq[15:8];
                write_command_count <= write_command_count + 32'd1;
            end

            // READ
            if (ras_n && !cas_n && we_n) begin
                if (!row_open || ba != open_ba) begin
                    $display("FAIL: SDRAM model 收到未打开 row/bank 的 READ");
                    $finish;
                end
                read_data <= mem[mem_key(open_row, ba, addr[8:0])];
                read_wait <= CAS_LATENCY_CYCLES;
                read_pending <= 1'b1;
                read_command_count <= read_command_count + 32'd1;
            end
        end
    end
end

endmodule
