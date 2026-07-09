// 最小字符型 VGA 渲染骨架。
// 当前目标不是做完整终端，而是先提供：
// 1. 可直接上板观察的 banner
// 2. 一个未来可被 MMIO 包装的单拍写口
// 3. 最小字模与字符 RAM 结构
//
// 已知限制：
// - 当前 cell 固定按 16x16 使用，内部把 8x8 字模水平/垂直各放大 2 倍。
// - 字符集由独立 font_rom_8x8 提供，只覆盖本阶段需要的少量字符；
//   未覆盖字符会显示为空。
// - reset 后先逐字清空 RAM，再写入默认 banner。这样做比较啰嗦，但比依赖综合器对大数组 initial 的支持更稳。
module vga_text_mode #(
    parameter integer CLK_DIV = 2,
    parameter integer H_VISIBLE = 640,
    parameter integer H_FRONT = 16,
    parameter integer H_SYNC = 96,
    parameter integer H_BACK = 48,
    parameter integer V_VISIBLE = 480,
    parameter integer V_FRONT = 10,
    parameter integer V_SYNC = 2,
    parameter integer V_BACK = 33,
    parameter integer TEXT_COLS = 40,
    parameter integer TEXT_ROWS = 30,
    parameter integer CELL_WIDTH = 16,
    parameter integer CELL_HEIGHT = 16,
    parameter integer BANNER_ROW = 2,
    parameter integer BANNER_COL = 2
) (
    input clk,
    input reset,
    input cell_we,
    input [5:0] cell_x,
    input [4:0] cell_y,
    input [7:0] cell_char,
    output reg vga_r,
    output reg vga_g,
    output reg vga_b,
    output     vga_hs,
    output     vga_vs
);

localparam integer CHAR_COUNT = TEXT_COLS * TEXT_ROWS;
localparam integer BANNER_LEN = 13;
localparam [1:0] INIT_CLEAR = 2'd0;
localparam [1:0] INIT_BANNER = 2'd1;
localparam [1:0] INIT_DONE = 2'd2;

reg [7:0] char_ram [0:CHAR_COUNT-1];
reg [1:0] init_state;
reg [11:0] init_index;
reg init_done;

wire pixel_tick;
wire [11:0] pixel_x;
wire [11:0] pixel_y;
wire active_video;
wire frame_start;
wire hsync;
wire vsync;

reg [7:0] current_char;
wire [7:0] current_glyph_row;
reg pixel_on;
integer write_index;
integer banner_index;
integer current_cell_x;
integer current_cell_y;
integer current_cell_index;
integer cell_pixel_x;
integer cell_pixel_y;
integer glyph_col;
integer glyph_row_index;

function [7:0] banner_char;
    input [3:0] index;
    begin
        case (index)
            4'd0: banner_char = "T";
            4'd1: banner_char = "E";
            4'd2: banner_char = "C";
            4'd3: banner_char = "P";
            4'd4: banner_char = "L";
            4'd5: banner_char = "U";
            4'd6: banner_char = "S";
            4'd7: banner_char = "R";
            4'd8: banner_char = "V";
            4'd9: banner_char = " ";
            4'd10: banner_char = "V";
            4'd11: banner_char = "G";
            default: banner_char = "A";
        endcase
    end
endfunction

font_rom_8x8 font_rom (
    .char_code(current_char),
    .row_index(glyph_row_index[2:0]),
    .row_pixels(current_glyph_row)
);

vga_timing_640x480 #(
    .CLK_DIV(CLK_DIV),
    .H_VISIBLE(H_VISIBLE),
    .H_FRONT(H_FRONT),
    .H_SYNC(H_SYNC),
    .H_BACK(H_BACK),
    .V_VISIBLE(V_VISIBLE),
    .V_FRONT(V_FRONT),
    .V_SYNC(V_SYNC),
    .V_BACK(V_BACK)
) timing (
    .clk(clk),
    .reset(reset),
    .pixel_tick(pixel_tick),
    .pixel_x(pixel_x),
    .pixel_y(pixel_y),
    .hsync(hsync),
    .vsync(vsync),
    .active_video(active_video),
    .frame_start(frame_start)
);

assign vga_hs = hsync;
assign vga_vs = vsync;

always @(posedge clk) begin
    if (reset) begin
        init_state <= INIT_CLEAR;
        init_index <= 12'd0;
        init_done <= 1'b0;
    end else if (init_state == INIT_CLEAR) begin
        char_ram[init_index] <= 8'h20;
        if (init_index >= CHAR_COUNT - 1) begin
            init_index <= 12'd0;
            init_state <= INIT_BANNER;
        end else begin
            init_index <= init_index + 12'd1;
        end
    end else if (init_state == INIT_BANNER) begin
        banner_index = (BANNER_ROW * TEXT_COLS) + BANNER_COL + init_index;
        if (banner_index < CHAR_COUNT) begin
            char_ram[banner_index] <= banner_char(init_index[3:0]);
        end
        if (init_index >= BANNER_LEN - 1) begin
            init_index <= 12'd0;
            init_state <= INIT_DONE;
            init_done <= 1'b1;
        end else begin
            init_index <= init_index + 12'd1;
        end
    end else begin
        init_done <= 1'b1;
        if (cell_we && (cell_x < TEXT_COLS) && (cell_y < TEXT_ROWS)) begin
            write_index = (cell_y * TEXT_COLS) + cell_x;
            char_ram[write_index] <= cell_char;
        end
    end
end

always @(*) begin
    current_char = 8'h20;
    pixel_on = 1'b0;
    current_cell_x = 0;
    current_cell_y = 0;
    current_cell_index = 0;
    cell_pixel_x = 0;
    cell_pixel_y = 0;
    glyph_col = 0;
    glyph_row_index = 0;

    if (active_video && init_done) begin
        current_cell_x = pixel_x / CELL_WIDTH;
        current_cell_y = pixel_y / CELL_HEIGHT;
        cell_pixel_x = pixel_x % CELL_WIDTH;
        cell_pixel_y = pixel_y % CELL_HEIGHT;

        if ((current_cell_x < TEXT_COLS) && (current_cell_y < TEXT_ROWS)) begin
            current_cell_index = (current_cell_y * TEXT_COLS) + current_cell_x;
            current_char = char_ram[current_cell_index];
            glyph_col = cell_pixel_x >> 1;
            glyph_row_index = cell_pixel_y >> 1;

            if (glyph_col < 8) begin
                pixel_on = current_glyph_row[7 - glyph_col];
            end
        end
    end
end

always @(*) begin
    if (active_video && pixel_on) begin
        vga_r = 1'b1;
        vga_g = 1'b1;
        vga_b = 1'b1;
    end else begin
        vga_r = 1'b0;
        vga_g = 1'b0;
        vga_b = 1'b0;
    end
end

endmodule
