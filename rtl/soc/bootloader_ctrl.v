// UART bootloader 控制器。
//
// command 1 保持 v1 wire format：
//   magic + version + command + bram_len + bram_payload + crc32
// command 2 用于快速装载完整 demo image：
//   magic + version + command + bram_len + sdram_addr + sdram_len
//   + bram_payload + sdram_payload + crc32
// 所有整数均为 little-endian。CRC32 覆盖 magic 之后、CRC 之前的全部字节。
// 初版按整包 ACK/重传；CRC 失败时 SDRAM 中可能有旧的半包，但 CPU 仍保持 reset，
// host 重传会覆盖同一地址范围。逐 chunk ACK 留给长视频版本。
module bootloader_ctrl #(
    parameter integer BRAM_ADDR_WIDTH = 14,
    parameter integer INTERBYTE_TIMEOUT_CYCLES = 50000000,
    parameter [31:0] SDRAM_BASE_ADDR = 32'h8000_0000,
    parameter [31:0] SDRAM_LIMIT_ADDR = 32'h8200_0000
) (
    input        clk,
    input        reset,

    input  [7:0] rx_data,
    input        rx_valid,
    input        rx_overrun,
    input        rx_framing_error,
    output reg   rx_ready,
    output reg   clear_rx_overrun,
    output reg   clear_rx_framing_error,

    input        tx_ready,
    output reg   tx_valid,
    output reg [7:0] tx_data,

    output reg                              bram_en,
    output reg [BRAM_ADDR_WIDTH-1:0]        bram_addr,
    output reg [31:0]                       bram_wdata,
    output reg [3:0]                        bram_wstrb,

    output reg        sdram_req_valid,
    input             sdram_req_ready,
    output reg [31:0] sdram_req_addr,
    output reg [31:0] sdram_req_wdata,
    output reg [3:0]  sdram_req_wstrb,
    input             sdram_resp_valid,
    input             sdram_resp_error,

    output reg   cpu_release,
    output reg [7:0] last_error
);

localparam [7:0] PROTOCOL_VERSION = 8'h01;
localparam [7:0] COMMAND_LOAD_AND_RUN = 8'h01;
localparam [7:0] COMMAND_LOAD_IMAGE   = 8'h02;

localparam [7:0] RESPONSE_READY = 8'h52;
localparam [7:0] RESPONSE_ACK   = 8'h79;
localparam [7:0] RESPONSE_NACK  = 8'h1f;

localparam [7:0] ERROR_NONE    = 8'h00;
localparam [7:0] ERROR_HEADER  = 8'h01;
localparam [7:0] ERROR_LENGTH  = 8'h02;
localparam [7:0] ERROR_UART    = 8'h03;
localparam [7:0] ERROR_CRC     = 8'h04;
localparam [7:0] ERROR_TIMEOUT = 8'h05;
localparam [7:0] ERROR_SDRAM   = 8'h06;

localparam [31:0] BRAM_BYTES = (32'd1 << BRAM_ADDR_WIDTH) * 32'd4;

localparam [4:0] STATE_CLEAR         = 5'd0;
localparam [4:0] STATE_SEND_0        = 5'd1;
localparam [4:0] STATE_SEND_1        = 5'd2;
localparam [4:0] STATE_DRAIN_BUSY    = 5'd3;
localparam [4:0] STATE_DRAIN_IDLE    = 5'd4;
localparam [4:0] STATE_MAGIC         = 5'd5;
localparam [4:0] STATE_VERSION       = 5'd6;
localparam [4:0] STATE_COMMAND       = 5'd7;
localparam [4:0] STATE_BRAM_LEN_0    = 5'd8;
localparam [4:0] STATE_BRAM_LEN_1    = 5'd9;
localparam [4:0] STATE_BRAM_LEN_2    = 5'd10;
localparam [4:0] STATE_BRAM_LEN_3    = 5'd11;
localparam [4:0] STATE_BRAM_PAYLOAD  = 5'd12;
localparam [4:0] STATE_SDRAM_ADDR_0  = 5'd13;
localparam [4:0] STATE_SDRAM_ADDR_1  = 5'd14;
localparam [4:0] STATE_SDRAM_ADDR_2  = 5'd15;
localparam [4:0] STATE_SDRAM_ADDR_3  = 5'd16;
localparam [4:0] STATE_SDRAM_LEN_0   = 5'd17;
localparam [4:0] STATE_SDRAM_LEN_1   = 5'd18;
localparam [4:0] STATE_SDRAM_LEN_2   = 5'd19;
localparam [4:0] STATE_SDRAM_LEN_3   = 5'd20;
localparam [4:0] STATE_SDRAM_PAYLOAD = 5'd21;
localparam [4:0] STATE_SDRAM_REQ     = 5'd22;
localparam [4:0] STATE_SDRAM_RESP    = 5'd23;
localparam [4:0] STATE_CRC_0         = 5'd24;
localparam [4:0] STATE_CRC_1         = 5'd25;
localparam [4:0] STATE_CRC_2         = 5'd26;
localparam [4:0] STATE_CRC_3         = 5'd27;
localparam [4:0] STATE_RUN           = 5'd28;

localparam AFTER_WAIT = 1'b0;
localparam AFTER_RUN  = 1'b1;

reg [4:0] state;
reg [1:0] magic_index;
reg [7:0] command;
reg [31:0] bram_len;
reg [31:0] bram_index;
reg [31:0] image_sdram_addr;
reg [31:0] sdram_len;
reg [31:0] sdram_index;
reg [31:0] sdram_word;
reg [31:0] sdram_write_addr;
reg [31:0] sdram_write_data;
reg [31:0] received_crc;
reg [31:0] crc_reg;
reg [31:0] timeout_count;
reg [BRAM_ADDR_WIDTH-1:0] clear_index;
reg [7:0] response_byte_0;
reg [7:0] response_byte_1;
reg after_response;

wire receive_state =
    state == STATE_VERSION || state == STATE_COMMAND ||
    state == STATE_BRAM_LEN_0 || state == STATE_BRAM_LEN_1 ||
    state == STATE_BRAM_LEN_2 || state == STATE_BRAM_LEN_3 ||
    state == STATE_BRAM_PAYLOAD ||
    state == STATE_SDRAM_ADDR_0 || state == STATE_SDRAM_ADDR_1 ||
    state == STATE_SDRAM_ADDR_2 || state == STATE_SDRAM_ADDR_3 ||
    state == STATE_SDRAM_LEN_0 || state == STATE_SDRAM_LEN_1 ||
    state == STATE_SDRAM_LEN_2 || state == STATE_SDRAM_LEN_3 ||
    state == STATE_SDRAM_PAYLOAD ||
    state == STATE_CRC_0 || state == STATE_CRC_1 ||
    state == STATE_CRC_2 || state == STATE_CRC_3;

function [31:0] crc32_byte;
    input [31:0] crc;
    input [7:0] data;
    reg [31:0] value;
    integer i;
    begin
        value = crc ^ {24'h000000, data};
        for (i = 0; i < 8; i = i + 1) begin
            if (value[0])
                value = (value >> 1) ^ 32'hedb88320;
            else
                value = value >> 1;
        end
        crc32_byte = value;
    end
endfunction

always @(*) begin
    rx_ready = 1'b0;
    tx_valid = 1'b0;
    tx_data = 8'h00;
    bram_en = 1'b0;
    bram_addr = {BRAM_ADDR_WIDTH{1'b0}};
    bram_wdata = 32'h0000_0000;
    bram_wstrb = 4'b0000;
    sdram_req_valid = 1'b0;
    sdram_req_addr = sdram_write_addr;
    sdram_req_wdata = sdram_write_data;
    sdram_req_wstrb = 4'b1111;

    if (state == STATE_CLEAR) begin
        bram_en = 1'b1;
        bram_addr = clear_index;
        bram_wstrb = 4'b1111;
    end else if (state == STATE_SEND_0) begin
        tx_valid = 1'b1;
        tx_data = response_byte_0;
    end else if (state == STATE_SEND_1) begin
        tx_valid = 1'b1;
        tx_data = response_byte_1;
    end else if (state == STATE_MAGIC || receive_state) begin
        rx_ready = 1'b1;
        if (state == STATE_BRAM_PAYLOAD && rx_valid) begin
            bram_en = 1'b1;
            bram_addr = bram_index[BRAM_ADDR_WIDTH+1:2];
            case (bram_index[1:0])
                2'd0: begin bram_wdata = {24'h0, rx_data}; bram_wstrb = 4'b0001; end
                2'd1: begin bram_wdata = {16'h0, rx_data, 8'h0}; bram_wstrb = 4'b0010; end
                2'd2: begin bram_wdata = {8'h0, rx_data, 16'h0}; bram_wstrb = 4'b0100; end
                default: begin bram_wdata = {rx_data, 24'h0}; bram_wstrb = 4'b1000; end
            endcase
        end
    end else if (state == STATE_SDRAM_REQ) begin
        sdram_req_valid = 1'b1;
    end
end

always @(posedge clk) begin
    if (reset) begin
        state <= STATE_CLEAR;
        magic_index <= 2'd0;
        command <= 8'h00;
        bram_len <= 32'd0;
        bram_index <= 32'd0;
        image_sdram_addr <= 32'd0;
        sdram_len <= 32'd0;
        sdram_index <= 32'd0;
        sdram_word <= 32'd0;
        sdram_write_addr <= 32'd0;
        sdram_write_data <= 32'd0;
        received_crc <= 32'd0;
        crc_reg <= 32'hffff_ffff;
        timeout_count <= 32'd0;
        clear_index <= {BRAM_ADDR_WIDTH{1'b0}};
        response_byte_0 <= RESPONSE_READY;
        response_byte_1 <= ERROR_NONE;
        after_response <= AFTER_WAIT;
        cpu_release <= 1'b0;
        last_error <= ERROR_NONE;
        clear_rx_overrun <= 1'b0;
        clear_rx_framing_error <= 1'b0;
    end else begin
        clear_rx_overrun <= 1'b0;
        clear_rx_framing_error <= 1'b0;

        if (receive_state && (rx_overrun || rx_framing_error)) begin
            state <= STATE_CLEAR;
            clear_index <= {BRAM_ADDR_WIDTH{1'b0}};
            response_byte_0 <= RESPONSE_NACK;
            response_byte_1 <= ERROR_UART;
            after_response <= AFTER_WAIT;
            last_error <= ERROR_UART;
            timeout_count <= 32'd0;
            clear_rx_overrun <= 1'b1;
            clear_rx_framing_error <= 1'b1;
        end else if (receive_state && !rx_valid && INTERBYTE_TIMEOUT_CYCLES > 0 &&
                     timeout_count >= INTERBYTE_TIMEOUT_CYCLES - 1) begin
            state <= STATE_CLEAR;
            clear_index <= {BRAM_ADDR_WIDTH{1'b0}};
            response_byte_0 <= RESPONSE_NACK;
            response_byte_1 <= ERROR_TIMEOUT;
            after_response <= AFTER_WAIT;
            last_error <= ERROR_TIMEOUT;
            timeout_count <= 32'd0;
        end else begin
            if (receive_state) begin
                if (rx_valid && rx_ready)
                    timeout_count <= 32'd0;
                else if (INTERBYTE_TIMEOUT_CYCLES > 0)
                    timeout_count <= timeout_count + 1'b1;
            end else begin
                timeout_count <= 32'd0;
            end

            case (state)
                STATE_CLEAR: begin
                    cpu_release <= 1'b0;
                    if (clear_index == {BRAM_ADDR_WIDTH{1'b1}}) begin
                        clear_index <= {BRAM_ADDR_WIDTH{1'b0}};
                        state <= STATE_SEND_0;
                    end else begin
                        clear_index <= clear_index + 1'b1;
                    end
                end

                STATE_SEND_0: if (tx_valid && tx_ready) state <= STATE_SEND_1;
                STATE_SEND_1: if (tx_valid && tx_ready) state <= STATE_DRAIN_BUSY;
                STATE_DRAIN_BUSY: if (!tx_ready) state <= STATE_DRAIN_IDLE;
                STATE_DRAIN_IDLE: begin
                    if (tx_ready) begin
                        if (after_response == AFTER_RUN) begin
                            cpu_release <= 1'b1;
                            state <= STATE_RUN;
                        end else begin
                            magic_index <= 2'd0;
                            state <= STATE_MAGIC;
                        end
                    end
                end

                STATE_MAGIC: begin
                    if (rx_valid && rx_ready) begin
                        case (magic_index)
                            2'd0: magic_index <= (rx_data == 8'h1e) ? 2'd1 : 2'd0;
                            2'd1: magic_index <= (rx_data == 8'hbb) ? 2'd2 :
                                                      ((rx_data == 8'h1e) ? 2'd1 : 2'd0);
                            2'd2: magic_index <= (rx_data == 8'hda) ? 2'd3 :
                                                      ((rx_data == 8'h1e) ? 2'd1 : 2'd0);
                            default: begin
                                if (rx_data == 8'hba) begin
                                    magic_index <= 2'd0;
                                    crc_reg <= 32'hffff_ffff;
                                    bram_len <= 32'd0;
                                    bram_index <= 32'd0;
                                    image_sdram_addr <= 32'd0;
                                    sdram_len <= 32'd0;
                                    sdram_index <= 32'd0;
                                    received_crc <= 32'd0;
                                    state <= STATE_VERSION;
                                end else begin
                                    magic_index <= (rx_data == 8'h1e) ? 2'd1 : 2'd0;
                                end
                            end
                        endcase
                    end
                end

                STATE_VERSION: begin
                    if (rx_valid && rx_ready) begin
                        crc_reg <= crc32_byte(crc_reg, rx_data);
                        if (rx_data == PROTOCOL_VERSION) state <= STATE_COMMAND;
                        else begin
                            state <= STATE_CLEAR; clear_index <= 0;
                            response_byte_0 <= RESPONSE_NACK; response_byte_1 <= ERROR_HEADER;
                            after_response <= AFTER_WAIT; last_error <= ERROR_HEADER;
                        end
                    end
                end

                STATE_COMMAND: begin
                    if (rx_valid && rx_ready) begin
                        command <= rx_data;
                        crc_reg <= crc32_byte(crc_reg, rx_data);
                        if (rx_data == COMMAND_LOAD_AND_RUN || rx_data == COMMAND_LOAD_IMAGE)
                            state <= STATE_BRAM_LEN_0;
                        else begin
                            state <= STATE_CLEAR; clear_index <= 0;
                            response_byte_0 <= RESPONSE_NACK; response_byte_1 <= ERROR_HEADER;
                            after_response <= AFTER_WAIT; last_error <= ERROR_HEADER;
                        end
                    end
                end

                STATE_BRAM_LEN_0: begin
                    if (rx_valid && rx_ready) begin
                        bram_len[7:0] <= rx_data; crc_reg <= crc32_byte(crc_reg, rx_data);
                        state <= STATE_BRAM_LEN_1;
                    end
                end
                STATE_BRAM_LEN_1: begin
                    if (rx_valid && rx_ready) begin
                        bram_len[15:8] <= rx_data; crc_reg <= crc32_byte(crc_reg, rx_data);
                        state <= STATE_BRAM_LEN_2;
                    end
                end
                STATE_BRAM_LEN_2: begin
                    if (rx_valid && rx_ready) begin
                        bram_len[23:16] <= rx_data; crc_reg <= crc32_byte(crc_reg, rx_data);
                        state <= STATE_BRAM_LEN_3;
                    end
                end
                STATE_BRAM_LEN_3: begin
                    if (rx_valid && rx_ready) begin
                        bram_len[31:24] <= rx_data; crc_reg <= crc32_byte(crc_reg, rx_data);
                        bram_index <= 32'd0;
                        if ({rx_data, bram_len[23:0]} == 0 ||
                            {rx_data, bram_len[23:0]} > BRAM_BYTES) begin
                            state <= STATE_CLEAR; clear_index <= 0;
                            response_byte_0 <= RESPONSE_NACK; response_byte_1 <= ERROR_LENGTH;
                            after_response <= AFTER_WAIT; last_error <= ERROR_LENGTH;
                        end else if (command == COMMAND_LOAD_IMAGE) begin
                            state <= STATE_SDRAM_ADDR_0;
                        end else begin
                            state <= STATE_BRAM_PAYLOAD;
                        end
                    end
                end

                STATE_SDRAM_ADDR_0: begin
                    if (rx_valid && rx_ready) begin
                        image_sdram_addr[7:0] <= rx_data; crc_reg <= crc32_byte(crc_reg, rx_data);
                        state <= STATE_SDRAM_ADDR_1;
                    end
                end
                STATE_SDRAM_ADDR_1: begin
                    if (rx_valid && rx_ready) begin
                        image_sdram_addr[15:8] <= rx_data; crc_reg <= crc32_byte(crc_reg, rx_data);
                        state <= STATE_SDRAM_ADDR_2;
                    end
                end
                STATE_SDRAM_ADDR_2: begin
                    if (rx_valid && rx_ready) begin
                        image_sdram_addr[23:16] <= rx_data; crc_reg <= crc32_byte(crc_reg, rx_data);
                        state <= STATE_SDRAM_ADDR_3;
                    end
                end
                STATE_SDRAM_ADDR_3: begin
                    if (rx_valid && rx_ready) begin
                        image_sdram_addr[31:24] <= rx_data; crc_reg <= crc32_byte(crc_reg, rx_data);
                        state <= STATE_SDRAM_LEN_0;
                    end
                end
                STATE_SDRAM_LEN_0: begin
                    if (rx_valid && rx_ready) begin
                        sdram_len[7:0] <= rx_data; crc_reg <= crc32_byte(crc_reg, rx_data);
                        state <= STATE_SDRAM_LEN_1;
                    end
                end
                STATE_SDRAM_LEN_1: begin
                    if (rx_valid && rx_ready) begin
                        sdram_len[15:8] <= rx_data; crc_reg <= crc32_byte(crc_reg, rx_data);
                        state <= STATE_SDRAM_LEN_2;
                    end
                end
                STATE_SDRAM_LEN_2: begin
                    if (rx_valid && rx_ready) begin
                        sdram_len[23:16] <= rx_data; crc_reg <= crc32_byte(crc_reg, rx_data);
                        state <= STATE_SDRAM_LEN_3;
                    end
                end
                STATE_SDRAM_LEN_3: begin
                    if (rx_valid && rx_ready) begin
                        sdram_len[31:24] <= rx_data; crc_reg <= crc32_byte(crc_reg, rx_data);
                        sdram_index <= 32'd0;
                        if ({rx_data, sdram_len[23:0]} == 0 ||
                            sdram_len[1:0] != 0 ||
                            image_sdram_addr[1:0] != 0 ||
                            image_sdram_addr < SDRAM_BASE_ADDR ||
                            image_sdram_addr >= SDRAM_LIMIT_ADDR ||
                            {rx_data, sdram_len[23:0]} > SDRAM_LIMIT_ADDR - image_sdram_addr) begin
                            state <= STATE_CLEAR; clear_index <= 0;
                            response_byte_0 <= RESPONSE_NACK; response_byte_1 <= ERROR_LENGTH;
                            after_response <= AFTER_WAIT; last_error <= ERROR_LENGTH;
                        end else begin
                            state <= STATE_BRAM_PAYLOAD;
                        end
                    end
                end

                STATE_BRAM_PAYLOAD: begin
                    if (rx_valid && rx_ready) begin
                        crc_reg <= crc32_byte(crc_reg, rx_data);
                        bram_index <= bram_index + 1'b1;
                        if (bram_index + 1'b1 == bram_len) begin
                            if (command == COMMAND_LOAD_IMAGE)
                                state <= STATE_SDRAM_PAYLOAD;
                            else
                                state <= STATE_CRC_0;
                        end
                    end
                end

                STATE_SDRAM_PAYLOAD: begin
                    if (rx_valid && rx_ready) begin
                        crc_reg <= crc32_byte(crc_reg, rx_data);
                        sdram_index <= sdram_index + 1'b1;
                        case (sdram_index[1:0])
                            2'd0: sdram_word[7:0] <= rx_data;
                            2'd1: sdram_word[15:8] <= rx_data;
                            2'd2: sdram_word[23:16] <= rx_data;
                            default: begin
                                sdram_write_data <= {rx_data, sdram_word[23:0]};
                                sdram_write_addr <= image_sdram_addr + sdram_index - 3;
                                state <= STATE_SDRAM_REQ;
                            end
                        endcase
                    end
                end

                STATE_SDRAM_REQ: begin
                    if (sdram_req_valid && sdram_req_ready)
                        state <= STATE_SDRAM_RESP;
                end
                STATE_SDRAM_RESP: begin
                    if (sdram_resp_valid) begin
                        if (sdram_resp_error) begin
                            state <= STATE_CLEAR; clear_index <= 0;
                            response_byte_0 <= RESPONSE_NACK; response_byte_1 <= ERROR_SDRAM;
                            after_response <= AFTER_WAIT; last_error <= ERROR_SDRAM;
                        end else if (sdram_index == sdram_len) begin
                            state <= STATE_CRC_0;
                        end else begin
                            state <= STATE_SDRAM_PAYLOAD;
                        end
                    end
                end

                STATE_CRC_0: begin
                    if (rx_valid && rx_ready) begin
                        received_crc[7:0] <= rx_data; state <= STATE_CRC_1;
                    end
                end
                STATE_CRC_1: begin
                    if (rx_valid && rx_ready) begin
                        received_crc[15:8] <= rx_data; state <= STATE_CRC_2;
                    end
                end
                STATE_CRC_2: begin
                    if (rx_valid && rx_ready) begin
                        received_crc[23:16] <= rx_data; state <= STATE_CRC_3;
                    end
                end
                STATE_CRC_3: begin
                    if (rx_valid && rx_ready) begin
                        received_crc[31:24] <= rx_data;
                        if ({rx_data, received_crc[23:0]} == ~crc_reg) begin
                            response_byte_0 <= RESPONSE_ACK; response_byte_1 <= ERROR_NONE;
                            after_response <= AFTER_RUN; last_error <= ERROR_NONE;
                            state <= STATE_SEND_0;
                        end else begin
                            state <= STATE_CLEAR; clear_index <= 0;
                            response_byte_0 <= RESPONSE_NACK; response_byte_1 <= ERROR_CRC;
                            after_response <= AFTER_WAIT; last_error <= ERROR_CRC;
                        end
                    end
                end

                STATE_RUN: cpu_release <= 1'b1;

                default: begin
                    state <= STATE_CLEAR; clear_index <= 0;
                    response_byte_0 <= RESPONSE_NACK; response_byte_1 <= ERROR_HEADER;
                    after_response <= AFTER_WAIT; last_error <= ERROR_HEADER;
                    cpu_release <= 1'b0;
                end
            endcase
        end
    end
end

endmodule
