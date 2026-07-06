module sdram_smoke_ctrl #(
    parameter integer PWRUP_WAIT_CYCLES = 16'd10000,
    parameter integer TRP_CYCLES = 16'd3,
    parameter integer TRFC_CYCLES = 16'd7,
    parameter integer TMRD_CYCLES = 16'd2,
    parameter integer TRCD_CYCLES = 16'd3,
    parameter integer TWR_CYCLES = 16'd3,
    parameter integer CAS_LATENCY_CYCLES = 16'd2,
    parameter [12:0] MODE_REG_VALUE = 13'h220,
    parameter [12:0] ROW_ADDR = 13'd0,
    parameter [9:0]  COL_ADDR = 10'd0,
    parameter [15:0] TEST_DATA = 16'hA55A
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
    output reg    done_pass,
    output reg    done_fail
);

localparam [4:0]
    ST_PWRUP_WAIT = 5'd0,
    ST_PRECHARGE  = 5'd1,
    ST_WAIT_TRP   = 5'd2,
    ST_AR1        = 5'd3,
    ST_WAIT_TRFC1 = 5'd4,
    ST_AR2        = 5'd5,
    ST_WAIT_TRFC2 = 5'd6,
    ST_MRS        = 5'd7,
    ST_WAIT_TMRD  = 5'd8,
    ST_ACT_WRITE  = 5'd9,
    ST_WAIT_TRCD1 = 5'd10,
    ST_WRITE      = 5'd11,
    ST_WAIT_TWR   = 5'd12,
    ST_ACT_READ   = 5'd13,
    ST_WAIT_TRCD2 = 5'd14,
    ST_READ       = 5'd15,
    ST_WAIT_CL    = 5'd16,
    ST_SAMPLE     = 5'd17,
    ST_PASS       = 5'd18,
    ST_FAIL       = 5'd19;

localparam [12:0] COL_ADDR_WITH_AP = {2'b00, 1'b1, COL_ADDR};

reg [4:0]  state;
reg [15:0] wait_count;

always @(posedge clk) begin
    if (reset) begin
        state <= ST_PWRUP_WAIT;
        wait_count <= 16'd0;
        dq_oe <= 1'b0;
        dq_out <= TEST_DATA;
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
        dq_oe <= 1'b0;
        dq_out <= TEST_DATA;
        sdram_cke <= 1'b1;
        sdram_cs_n <= 1'b0;
        sdram_ras_n <= 1'b1;
        sdram_cas_n <= 1'b1;
        sdram_we_n <= 1'b1;
        sdram_ba <= 2'b00;
        sdram_addr <= 13'd0;
        sdram_dqm <= 2'b00;

        case (state)
            ST_PWRUP_WAIT: begin
                status_led <= 4'b0001;
                if (wait_count >= PWRUP_WAIT_CYCLES - 1) begin
                    wait_count <= 16'd0;
                    state <= ST_PRECHARGE;
                end else begin
                    wait_count <= wait_count + 16'd1;
                end
            end

            ST_PRECHARGE: begin
                status_led <= 4'b0001;
                sdram_ras_n <= 1'b0;
                sdram_we_n <= 1'b0;
                sdram_addr[10] <= 1'b1;
                wait_count <= 16'd0;
                state <= ST_WAIT_TRP;
            end

            ST_WAIT_TRP: begin
                status_led <= 4'b0001;
                if (wait_count >= TRP_CYCLES - 1) begin
                    wait_count <= 16'd0;
                    state <= ST_AR1;
                end else begin
                    wait_count <= wait_count + 16'd1;
                end
            end

            ST_AR1: begin
                status_led <= 4'b0001;
                sdram_ras_n <= 1'b0;
                sdram_cas_n <= 1'b0;
                wait_count <= 16'd0;
                state <= ST_WAIT_TRFC1;
            end

            ST_WAIT_TRFC1: begin
                status_led <= 4'b0001;
                if (wait_count >= TRFC_CYCLES - 1) begin
                    wait_count <= 16'd0;
                    state <= ST_AR2;
                end else begin
                    wait_count <= wait_count + 16'd1;
                end
            end

            ST_AR2: begin
                status_led <= 4'b0001;
                sdram_ras_n <= 1'b0;
                sdram_cas_n <= 1'b0;
                wait_count <= 16'd0;
                state <= ST_WAIT_TRFC2;
            end

            ST_WAIT_TRFC2: begin
                status_led <= 4'b0001;
                if (wait_count >= TRFC_CYCLES - 1) begin
                    wait_count <= 16'd0;
                    state <= ST_MRS;
                end else begin
                    wait_count <= wait_count + 16'd1;
                end
            end

            ST_MRS: begin
                status_led <= 4'b0001;
                sdram_ras_n <= 1'b0;
                sdram_cas_n <= 1'b0;
                sdram_we_n <= 1'b0;
                sdram_addr <= MODE_REG_VALUE;
                wait_count <= 16'd0;
                state <= ST_WAIT_TMRD;
            end

            ST_WAIT_TMRD: begin
                status_led <= 4'b0001;
                if (wait_count >= TMRD_CYCLES - 1) begin
                    wait_count <= 16'd0;
                    state <= ST_ACT_WRITE;
                end else begin
                    wait_count <= wait_count + 16'd1;
                end
            end

            ST_ACT_WRITE: begin
                status_led <= 4'b0010;
                sdram_ras_n <= 1'b0;
                sdram_ba <= 2'b00;
                sdram_addr <= ROW_ADDR;
                wait_count <= 16'd0;
                state <= ST_WAIT_TRCD1;
            end

            ST_WAIT_TRCD1: begin
                status_led <= 4'b0010;
                if (wait_count >= TRCD_CYCLES - 1) begin
                    wait_count <= 16'd0;
                    state <= ST_WRITE;
                end else begin
                    wait_count <= wait_count + 16'd1;
                end
            end

            ST_WRITE: begin
                status_led <= 4'b0010;
                dq_oe <= 1'b1;
                dq_out <= TEST_DATA;
                sdram_cas_n <= 1'b0;
                sdram_we_n <= 1'b0;
                sdram_ba <= 2'b00;
                sdram_addr <= COL_ADDR_WITH_AP;
                wait_count <= 16'd0;
                state <= ST_WAIT_TWR;
            end

            ST_WAIT_TWR: begin
                status_led <= 4'b0010;
                if (wait_count >= TWR_CYCLES - 1) begin
                    wait_count <= 16'd0;
                    state <= ST_ACT_READ;
                end else begin
                    wait_count <= wait_count + 16'd1;
                end
            end

            ST_ACT_READ: begin
                status_led <= 4'b0100;
                sdram_ras_n <= 1'b0;
                sdram_ba <= 2'b00;
                sdram_addr <= ROW_ADDR;
                wait_count <= 16'd0;
                state <= ST_WAIT_TRCD2;
            end

            ST_WAIT_TRCD2: begin
                status_led <= 4'b0100;
                if (wait_count >= TRCD_CYCLES - 1) begin
                    wait_count <= 16'd0;
                    state <= ST_READ;
                end else begin
                    wait_count <= wait_count + 16'd1;
                end
            end

            ST_READ: begin
                status_led <= 4'b0100;
                sdram_cas_n <= 1'b0;
                sdram_ba <= 2'b00;
                sdram_addr <= COL_ADDR_WITH_AP;
                wait_count <= 16'd0;
                state <= ST_WAIT_CL;
            end

            ST_WAIT_CL: begin
                status_led <= 4'b0100;
                if (wait_count >= CAS_LATENCY_CYCLES - 1) begin
                    wait_count <= 16'd0;
                    state <= ST_SAMPLE;
                end else begin
                    wait_count <= wait_count + 16'd1;
                end
            end

            ST_SAMPLE: begin
                if (dq_in == TEST_DATA) begin
                    status_led <= 4'b1000;
                    done_pass <= 1'b1;
                    state <= ST_PASS;
                end else begin
                    status_led <= 4'b1111;
                    done_fail <= 1'b1;
                    state <= ST_FAIL;
                end
            end

            ST_PASS: begin
                status_led <= 4'b1000;
            end

            default: begin
                status_led <= 4'b1111;
            end
        endcase
    end
end

endmodule
