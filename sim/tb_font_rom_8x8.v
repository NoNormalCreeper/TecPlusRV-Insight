// Representative checks for the reusable 8x8 font ROM.
`timescale 1ns/1ps

module tb_font_rom_8x8;

reg [7:0] char_code;
reg [2:0] row_index;
wire [7:0] row_pixels;

font_rom_8x8 dut (
    .char_code(char_code),
    .row_index(row_index),
    .row_pixels(row_pixels)
);

task expect_row;
    input [7:0] code;
    input [2:0] row;
    input [7:0] expected;
    begin
        char_code = code;
        row_index = row;
        #1;
        if (row_pixels !== expected) begin
            $display(
                "FAIL: char=%02x row=%0d expected=%02x got=%02x",
                code,
                row,
                expected,
                row_pixels
            );
            $finish;
        end
    end
endtask

initial begin
    expect_row("A", 3'd0, 8'h18);
    expect_row("A", 3'd4, 8'h7e);
    expect_row("0", 3'd3, 8'h52);
    expect_row("5", 3'd2, 8'h7c);
    expect_row("-", 3'd3, 8'h3c);
    expect_row(":", 3'd1, 8'h18);
    expect_row(":", 3'd2, 8'h00);
    expect_row("A", 3'd7, 8'h00);
    expect_row("B", 3'd0, 8'h00);

    $display("PASS: font_rom_8x8 glyph rows and blank fallback");
    $finish;
end

endmodule
