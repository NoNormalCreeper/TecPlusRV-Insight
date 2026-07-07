// Probe 4 的独立 SDRAM tester。
// 它比 Probe 4a 多做一段地址窗口的重复写读校验，但仍不是 SoC 级通用控制器：
// 不提供总线接口、不做运行时/bootloader，也不把 SDRAM 映射给 CPU。
module sdram_tester_ctrl #(
    parameter integer PWRUP_WAIT_CYCLES = 16'd10000,
    parameter integer TRP_CYCLES = 16'd3,
    parameter integer TRFC_CYCLES = 16'd7,
    parameter integer TMRD_CYCLES = 16'd2,
    parameter integer TRCD_CYCLES = 16'd3,
    parameter integer TWR_CYCLES = 16'd3,
    parameter integer CAS_LATENCY_CYCLES = 16'd2,
    parameter integer PASS_HOLD_CYCLES = 32'd25000000,
    // 当前地址发生器只扫同一 row 的 10-bit column 窗口，TEST_WORDS 应保持 <= 1024。
    parameter integer TEST_WORDS = 256,
    parameter [12:0] MODE_REG_VALUE = 13'h220,
    parameter [12:0] ROW_ADDR = 13'd0
) (
    input         clk,
    input         reset,
    input  [15:0] dq_in,
    output reg    dq_oe,
    output reg [15:0] dq_out,
    output reg    sdram_cke,
    output reg    sdram_cs_n,
    output reg    sdram_ras_n,
    output reg    sdram_cas_n,
    output reg    sdram_we_n,
    output reg [1:0] sdram_ba,
    output reg [12:0] sdram_addr,
    output reg [1:0] sdram_dqm,
    output reg [3:0] status_led,
    output reg [9:0] test_index,
    output reg [7:0] pass_count,
    output reg    done_pass,
    output reg    done_fail
);

localparam [4:0]
    ST_PWRUP_WAIT     = 5'd0,
    ST_PRECHARGE      = 5'd1,
    ST_WAIT_TRP       = 5'd2,
    ST_AR1            = 5'd3,
    ST_WAIT_TRFC1     = 5'd4,
    ST_AR2            = 5'd5,
    ST_WAIT_TRFC2     = 5'd6,
    ST_MRS            = 5'd7,
    ST_WAIT_TMRD      = 5'd8,
    ST_ACT_WRITE      = 5'd9,
    ST_WAIT_TRCD_WR   = 5'd10,
    ST_WRITE          = 5'd11,
    ST_WAIT_TWR       = 5'd12,
    ST_WAIT_WTRP      = 5'd13,
    ST_NEXT_WRITE     = 5'd14,
    ST_ACT_READ       = 5'd15,
    ST_WAIT_TRCD_RD   = 5'd16,
    ST_READ           = 5'd17,
    ST_WAIT_CL        = 5'd18,
    ST_SAMPLE         = 5'd19,
    ST_WAIT_RTRP      = 5'd20,
    ST_NEXT_READ      = 5'd21,
    ST_PASS           = 5'd22,
    ST_PASS_HOLD      = 5'd23,
    ST_FAIL           = 5'd24;

reg [4:0]  state;
reg [31:0] wait_count;

wire [12:0] col_addr_with_ap;
wire [15:0] expected_data;

assign col_addr_with_ap = {2'b00, 1'b1, test_index};
assign expected_data = make_pattern(test_index, pass_count);

function [15:0] make_pattern;
    input [9:0] index;
    input [7:0] round;
    begin
        make_pattern = 16'hA55A ^ {index[7:0], index[9:2]} ^ {round, ~round};
    end
endfunction

always @(posedge clk) begin
    if (reset) begin
        state <= ST_PWRUP_WAIT;
        wait_count <= 32'd0;
        test_index <= 10'd0;
        pass_count <= 8'd0;
        dq_oe <= 1'b0;
        dq_out <= 16'h0000;
        sdram_cke <= 1'b1;
        sdram_cs_n <= 1'b0;
        sdram_ras_n <= 1'b1;
        sdram_cas_n <= 1'b1;
        sdram_we_n <= 1'b1;
        sdram_ba <= 2'b00;
        sdram_addr <= 13'd0;
        sdram_dqm <= 2'b00;
        status_led <= 4'b0001;
        done_pass <= 1'b0;
        done_fail <= 1'b0;
    end else begin
        // 默认输出 NOP。只有命令状态会覆盖 RAS/CAS/WE 和地址。
        dq_oe <= 1'b0;
        dq_out <= expected_data;
        sdram_cke <= 1'b1;
        sdram_cs_n <= 1'b0;
        sdram_ras_n <= 1'b1;
        sdram_cas_n <= 1'b1;
        sdram_we_n <= 1'b1;
        sdram_ba <= 2'b00;
        sdram_addr <= 13'd0;
        sdram_dqm <= 2'b00;
        done_pass <= 1'b0;

        case (state)
            ST_PWRUP_WAIT: begin
                status_led <= 4'b0001;
                if (wait_count >= PWRUP_WAIT_CYCLES - 1) begin
                    wait_count <= 32'd0;
                    state <= ST_PRECHARGE;
                end else begin
                    wait_count <= wait_count + 32'd1;
                end
            end

            ST_PRECHARGE: begin
                status_led <= 4'b0001;
                sdram_ras_n <= 1'b0;
                sdram_we_n <= 1'b0;
                sdram_addr[10] <= 1'b1;
                wait_count <= 32'd0;
                state <= ST_WAIT_TRP;
            end

            ST_WAIT_TRP: begin
                status_led <= 4'b0001;
                if (wait_count >= TRP_CYCLES - 1) begin
                    wait_count <= 32'd0;
                    state <= ST_AR1;
                end else begin
                    wait_count <= wait_count + 32'd1;
                end
            end

            ST_AR1: begin
                status_led <= 4'b0001;
                sdram_ras_n <= 1'b0;
                sdram_cas_n <= 1'b0;
                wait_count <= 32'd0;
                state <= ST_WAIT_TRFC1;
            end

            ST_WAIT_TRFC1: begin
                status_led <= 4'b0001;
                if (wait_count >= TRFC_CYCLES - 1) begin
                    wait_count <= 32'd0;
                    state <= ST_AR2;
                end else begin
                    wait_count <= wait_count + 32'd1;
                end
            end

            ST_AR2: begin
                status_led <= 4'b0001;
                sdram_ras_n <= 1'b0;
                sdram_cas_n <= 1'b0;
                wait_count <= 32'd0;
                state <= ST_WAIT_TRFC2;
            end

            ST_WAIT_TRFC2: begin
                status_led <= 4'b0001;
                if (wait_count >= TRFC_CYCLES - 1) begin
                    wait_count <= 32'd0;
                    state <= ST_MRS;
                end else begin
                    wait_count <= wait_count + 32'd1;
                end
            end

            ST_MRS: begin
                status_led <= 4'b0001;
                sdram_ras_n <= 1'b0;
                sdram_cas_n <= 1'b0;
                sdram_we_n <= 1'b0;
                sdram_addr <= MODE_REG_VALUE;
                wait_count <= 32'd0;
                test_index <= 10'd0;
                state <= ST_WAIT_TMRD;
            end

            ST_WAIT_TMRD: begin
                status_led <= 4'b0001;
                if (wait_count >= TMRD_CYCLES - 1) begin
                    wait_count <= 32'd0;
                    state <= ST_ACT_WRITE;
                end else begin
                    wait_count <= wait_count + 32'd1;
                end
            end

            ST_ACT_WRITE: begin
                status_led <= 4'b0010;
                sdram_ras_n <= 1'b0;
                sdram_ba <= 2'b00;
                sdram_addr <= ROW_ADDR;
                wait_count <= 32'd0;
                state <= ST_WAIT_TRCD_WR;
            end

            ST_WAIT_TRCD_WR: begin
                status_led <= 4'b0010;
                if (wait_count >= TRCD_CYCLES - 1) begin
                    wait_count <= 32'd0;
                    state <= ST_WRITE;
                end else begin
                    wait_count <= wait_count + 32'd1;
                end
            end

            ST_WRITE: begin
                status_led <= 4'b0010;
                dq_oe <= 1'b1;
                dq_out <= expected_data;
                sdram_cas_n <= 1'b0;
                sdram_we_n <= 1'b0;
                sdram_ba <= 2'b00;
                sdram_addr <= col_addr_with_ap;
                wait_count <= 32'd0;
                state <= ST_WAIT_TWR;
            end

            ST_WAIT_TWR: begin
                status_led <= 4'b0010;
                if (wait_count >= TWR_CYCLES - 1) begin
                    wait_count <= 32'd0;
                    state <= ST_WAIT_WTRP;
                end else begin
                    wait_count <= wait_count + 32'd1;
                end
            end

            ST_WAIT_WTRP: begin
                status_led <= 4'b0010;
                if (wait_count >= TRP_CYCLES - 1) begin
                    wait_count <= 32'd0;
                    state <= ST_NEXT_WRITE;
                end else begin
                    wait_count <= wait_count + 32'd1;
                end
            end

            ST_NEXT_WRITE: begin
                if (test_index >= TEST_WORDS - 1) begin
                    test_index <= 10'd0;
                    wait_count <= 32'd0;
                    state <= ST_ACT_READ;
                end else begin
                    test_index <= test_index + 10'd1;
                    wait_count <= 32'd0;
                    state <= ST_ACT_WRITE;
                end
            end

            ST_ACT_READ: begin
                status_led <= 4'b0100;
                sdram_ras_n <= 1'b0;
                sdram_ba <= 2'b00;
                sdram_addr <= ROW_ADDR;
                wait_count <= 32'd0;
                state <= ST_WAIT_TRCD_RD;
            end

            ST_WAIT_TRCD_RD: begin
                status_led <= 4'b0100;
                if (wait_count >= TRCD_CYCLES - 1) begin
                    wait_count <= 32'd0;
                    state <= ST_READ;
                end else begin
                    wait_count <= wait_count + 32'd1;
                end
            end

            ST_READ: begin
                status_led <= 4'b0100;
                sdram_cas_n <= 1'b0;
                sdram_ba <= 2'b00;
                sdram_addr <= col_addr_with_ap;
                wait_count <= 32'd0;
                state <= ST_WAIT_CL;
            end

            ST_WAIT_CL: begin
                status_led <= 4'b0100;
                if (wait_count >= CAS_LATENCY_CYCLES - 1) begin
                    wait_count <= 32'd0;
                    state <= ST_SAMPLE;
                end else begin
                    wait_count <= wait_count + 32'd1;
                end
            end

            ST_SAMPLE: begin
                status_led <= 4'b0100;
                if (dq_in == expected_data) begin
                    wait_count <= 32'd0;
                    state <= ST_WAIT_RTRP;
                end else begin
                    status_led <= 4'b1111;
                    done_fail <= 1'b1;
                    state <= ST_FAIL;
                end
            end

            ST_WAIT_RTRP: begin
                status_led <= 4'b0100;
                if (wait_count >= TRP_CYCLES - 1) begin
                    wait_count <= 32'd0;
                    state <= ST_NEXT_READ;
                end else begin
                    wait_count <= wait_count + 32'd1;
                end
            end

            ST_NEXT_READ: begin
                if (test_index >= TEST_WORDS - 1) begin
                    wait_count <= 32'd0;
                    state <= ST_PASS;
                end else begin
                    test_index <= test_index + 10'd1;
                    wait_count <= 32'd0;
                    state <= ST_ACT_READ;
                end
            end

            ST_PASS: begin
                status_led <= 4'b1000;
                done_pass <= 1'b1;
                wait_count <= 32'd0;
                state <= ST_PASS_HOLD;
            end

            ST_PASS_HOLD: begin
                status_led <= 4'b1000;
                if (wait_count >= PASS_HOLD_CYCLES - 1) begin
                    wait_count <= 32'd0;
                    test_index <= 10'd0;
                    pass_count <= pass_count + 8'd1;
                    state <= ST_ACT_WRITE;
                end else begin
                    wait_count <= wait_count + 32'd1;
                end
            end

            ST_FAIL: begin
                status_led <= 4'b1111;
                done_fail <= 1'b1;
            end

            default: begin
                status_led <= 4'b1111;
                done_fail <= 1'b1;
                state <= ST_FAIL;
            end
        endcase
    end
end

endmodule
