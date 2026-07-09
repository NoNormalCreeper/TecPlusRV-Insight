// Minimal reusable 8x8 bitmap font ROM.
// Unsupported characters and row 7 are blank.
module font_rom_8x8 (
    input  [7:0] char_code,
    input  [2:0] row_index,
    output [7:0] row_pixels
);

function [7:0] glyph_row;
    input [7:0] code;
    input [2:0] row;
    begin
        case (code)
            "A": begin
                case (row)
                    3'd0: glyph_row = 8'h18;
                    3'd1: glyph_row = 8'h24;
                    3'd2: glyph_row = 8'h42;
                    3'd3: glyph_row = 8'h42;
                    3'd4: glyph_row = 8'h7e;
                    3'd5: glyph_row = 8'h42;
                    3'd6: glyph_row = 8'h42;
                    default: glyph_row = 8'h00;
                endcase
            end
            "C": begin
                case (row)
                    3'd0: glyph_row = 8'h3c;
                    3'd1: glyph_row = 8'h42;
                    3'd2: glyph_row = 8'h40;
                    3'd3: glyph_row = 8'h40;
                    3'd4: glyph_row = 8'h40;
                    3'd5: glyph_row = 8'h42;
                    3'd6: glyph_row = 8'h3c;
                    default: glyph_row = 8'h00;
                endcase
            end
            "E": begin
                case (row)
                    3'd0: glyph_row = 8'h7e;
                    3'd1: glyph_row = 8'h40;
                    3'd2: glyph_row = 8'h40;
                    3'd3: glyph_row = 8'h7c;
                    3'd4: glyph_row = 8'h40;
                    3'd5: glyph_row = 8'h40;
                    3'd6: glyph_row = 8'h7e;
                    default: glyph_row = 8'h00;
                endcase
            end
            "G": begin
                case (row)
                    3'd0: glyph_row = 8'h3c;
                    3'd1: glyph_row = 8'h42;
                    3'd2: glyph_row = 8'h40;
                    3'd3: glyph_row = 8'h4e;
                    3'd4: glyph_row = 8'h42;
                    3'd5: glyph_row = 8'h46;
                    3'd6: glyph_row = 8'h3a;
                    default: glyph_row = 8'h00;
                endcase
            end
            "L": begin
                case (row)
                    3'd0: glyph_row = 8'h40;
                    3'd1: glyph_row = 8'h40;
                    3'd2: glyph_row = 8'h40;
                    3'd3: glyph_row = 8'h40;
                    3'd4: glyph_row = 8'h40;
                    3'd5: glyph_row = 8'h40;
                    3'd6: glyph_row = 8'h7e;
                    default: glyph_row = 8'h00;
                endcase
            end
            "P": begin
                case (row)
                    3'd0: glyph_row = 8'h7c;
                    3'd1: glyph_row = 8'h42;
                    3'd2: glyph_row = 8'h42;
                    3'd3: glyph_row = 8'h7c;
                    3'd4: glyph_row = 8'h40;
                    3'd5: glyph_row = 8'h40;
                    3'd6: glyph_row = 8'h40;
                    default: glyph_row = 8'h00;
                endcase
            end
            "R": begin
                case (row)
                    3'd0: glyph_row = 8'h7c;
                    3'd1: glyph_row = 8'h42;
                    3'd2: glyph_row = 8'h42;
                    3'd3: glyph_row = 8'h7c;
                    3'd4: glyph_row = 8'h48;
                    3'd5: glyph_row = 8'h44;
                    3'd6: glyph_row = 8'h42;
                    default: glyph_row = 8'h00;
                endcase
            end
            "S": begin
                case (row)
                    3'd0: glyph_row = 8'h3c;
                    3'd1: glyph_row = 8'h42;
                    3'd2: glyph_row = 8'h40;
                    3'd3: glyph_row = 8'h3c;
                    3'd4: glyph_row = 8'h02;
                    3'd5: glyph_row = 8'h42;
                    3'd6: glyph_row = 8'h3c;
                    default: glyph_row = 8'h00;
                endcase
            end
            "T": begin
                case (row)
                    3'd0: glyph_row = 8'h7e;
                    3'd1: glyph_row = 8'h18;
                    3'd2: glyph_row = 8'h18;
                    3'd3: glyph_row = 8'h18;
                    3'd4: glyph_row = 8'h18;
                    3'd5: glyph_row = 8'h18;
                    3'd6: glyph_row = 8'h18;
                    default: glyph_row = 8'h00;
                endcase
            end
            "U": begin
                case (row)
                    3'd0: glyph_row = 8'h42;
                    3'd1: glyph_row = 8'h42;
                    3'd2: glyph_row = 8'h42;
                    3'd3: glyph_row = 8'h42;
                    3'd4: glyph_row = 8'h42;
                    3'd5: glyph_row = 8'h42;
                    3'd6: glyph_row = 8'h3c;
                    default: glyph_row = 8'h00;
                endcase
            end
            "V": begin
                case (row)
                    3'd0: glyph_row = 8'h42;
                    3'd1: glyph_row = 8'h42;
                    3'd2: glyph_row = 8'h42;
                    3'd3: glyph_row = 8'h42;
                    3'd4: glyph_row = 8'h42;
                    3'd5: glyph_row = 8'h24;
                    3'd6: glyph_row = 8'h18;
                    default: glyph_row = 8'h00;
                endcase
            end
            "0": begin
                case (row)
                    3'd0: glyph_row = 8'h3c;
                    3'd1: glyph_row = 8'h46;
                    3'd2: glyph_row = 8'h4a;
                    3'd3: glyph_row = 8'h52;
                    3'd4: glyph_row = 8'h62;
                    3'd5: glyph_row = 8'h42;
                    3'd6: glyph_row = 8'h3c;
                    default: glyph_row = 8'h00;
                endcase
            end
            "1": begin
                case (row)
                    3'd0: glyph_row = 8'h18;
                    3'd1: glyph_row = 8'h28;
                    3'd2: glyph_row = 8'h08;
                    3'd3: glyph_row = 8'h08;
                    3'd4: glyph_row = 8'h08;
                    3'd5: glyph_row = 8'h08;
                    3'd6: glyph_row = 8'h3e;
                    default: glyph_row = 8'h00;
                endcase
            end
            "2": begin
                case (row)
                    3'd0: glyph_row = 8'h3c;
                    3'd1: glyph_row = 8'h42;
                    3'd2: glyph_row = 8'h02;
                    3'd3: glyph_row = 8'h0c;
                    3'd4: glyph_row = 8'h30;
                    3'd5: glyph_row = 8'h40;
                    3'd6: glyph_row = 8'h7e;
                    default: glyph_row = 8'h00;
                endcase
            end
            "3": begin
                case (row)
                    3'd0: glyph_row = 8'h3c;
                    3'd1: glyph_row = 8'h42;
                    3'd2: glyph_row = 8'h02;
                    3'd3: glyph_row = 8'h1c;
                    3'd4: glyph_row = 8'h02;
                    3'd5: glyph_row = 8'h42;
                    3'd6: glyph_row = 8'h3c;
                    default: glyph_row = 8'h00;
                endcase
            end
            "4": begin
                case (row)
                    3'd0: glyph_row = 8'h0c;
                    3'd1: glyph_row = 8'h14;
                    3'd2: glyph_row = 8'h24;
                    3'd3: glyph_row = 8'h44;
                    3'd4: glyph_row = 8'h7e;
                    3'd5: glyph_row = 8'h04;
                    3'd6: glyph_row = 8'h04;
                    default: glyph_row = 8'h00;
                endcase
            end
            "5": begin
                case (row)
                    3'd0: glyph_row = 8'h7e;
                    3'd1: glyph_row = 8'h40;
                    3'd2: glyph_row = 8'h7c;
                    3'd3: glyph_row = 8'h02;
                    3'd4: glyph_row = 8'h02;
                    3'd5: glyph_row = 8'h42;
                    3'd6: glyph_row = 8'h3c;
                    default: glyph_row = 8'h00;
                endcase
            end
            "6": begin
                case (row)
                    3'd0: glyph_row = 8'h1c;
                    3'd1: glyph_row = 8'h20;
                    3'd2: glyph_row = 8'h40;
                    3'd3: glyph_row = 8'h7c;
                    3'd4: glyph_row = 8'h42;
                    3'd5: glyph_row = 8'h42;
                    3'd6: glyph_row = 8'h3c;
                    default: glyph_row = 8'h00;
                endcase
            end
            "7": begin
                case (row)
                    3'd0: glyph_row = 8'h7e;
                    3'd1: glyph_row = 8'h02;
                    3'd2: glyph_row = 8'h04;
                    3'd3: glyph_row = 8'h08;
                    3'd4: glyph_row = 8'h10;
                    3'd5: glyph_row = 8'h10;
                    3'd6: glyph_row = 8'h10;
                    default: glyph_row = 8'h00;
                endcase
            end
            "8": begin
                case (row)
                    3'd0: glyph_row = 8'h3c;
                    3'd1: glyph_row = 8'h42;
                    3'd2: glyph_row = 8'h42;
                    3'd3: glyph_row = 8'h3c;
                    3'd4: glyph_row = 8'h42;
                    3'd5: glyph_row = 8'h42;
                    3'd6: glyph_row = 8'h3c;
                    default: glyph_row = 8'h00;
                endcase
            end
            "9": begin
                case (row)
                    3'd0: glyph_row = 8'h3c;
                    3'd1: glyph_row = 8'h42;
                    3'd2: glyph_row = 8'h42;
                    3'd3: glyph_row = 8'h3e;
                    3'd4: glyph_row = 8'h02;
                    3'd5: glyph_row = 8'h04;
                    3'd6: glyph_row = 8'h38;
                    default: glyph_row = 8'h00;
                endcase
            end
            "-": begin
                case (row)
                    3'd3: glyph_row = 8'h3c;
                    default: glyph_row = 8'h00;
                endcase
            end
            ":": begin
                case (row)
                    3'd1: glyph_row = 8'h18;
                    3'd4: glyph_row = 8'h18;
                    default: glyph_row = 8'h00;
                endcase
            end
            default: glyph_row = 8'h00;
        endcase
    end
endfunction

assign row_pixels = glyph_row(char_code, row_index);

endmodule
