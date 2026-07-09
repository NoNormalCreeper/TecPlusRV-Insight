// uart_rx behavior test: valid data, framing errors, overrun, and clearing.
`timescale 1ns/1ps

module tb_uart_rx;

localparam integer BIT_CLKS = 10;

reg clk;
reg reset;
reg rxd;
reg data_ready;
reg clear_overrun;
reg clear_framing_error;

wire [7:0] data_out;
wire data_valid;
wire overrun;
wire framing_error;

uart_rx #(
    .CLK_FREQ(100),
    .BAUD(10)
) dut (
    .clk(clk),
    .reset(reset),
    .rxd(rxd),
    .data_ready(data_ready),
    .clear_overrun(clear_overrun),
    .clear_framing_error(clear_framing_error),
    .data_out(data_out),
    .data_valid(data_valid),
    .overrun(overrun),
    .framing_error(framing_error)
);

always #5 clk = ~clk;

task drive_uart_frame;
    input [7:0] value;
    input       good_stop;
    integer i;
    begin
        @(negedge clk);
        rxd = 1'b0;
        repeat (BIT_CLKS) @(posedge clk);

        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            rxd = value[i];
            repeat (BIT_CLKS) @(posedge clk);
        end

        @(negedge clk);
        rxd = good_stop;
        repeat (BIT_CLKS) @(posedge clk);
        @(negedge clk);
        rxd = 1'b1;
        repeat (BIT_CLKS) @(posedge clk);
    end
endtask

task consume_byte;
    begin
        @(negedge clk);
        data_ready = 1'b1;
        @(negedge clk);
        data_ready = 1'b0;
    end
endtask

initial begin
    clk = 1'b0;
    reset = 1'b1;
    rxd = 1'b1;
    data_ready = 1'b0;
    clear_overrun = 1'b0;
    clear_framing_error = 1'b0;

    $dumpfile("sim/build/tb_uart_rx.vcd");
    $dumpvars(0, tb_uart_rx);

    repeat (4) @(posedge clk);
    reset = 1'b0;
    repeat (4) @(posedge clk);

    drive_uart_frame(8'ha5, 1'b1);
    if (!data_valid || data_out !== 8'ha5) begin
        $display("FAIL: RX expected a5, valid=%b data=%02x", data_valid, data_out);
        $finish;
    end

    consume_byte();
    if (data_valid) begin
        $display("FAIL: data_ready did not consume the buffered byte");
        $finish;
    end

    drive_uart_frame(8'h3c, 1'b0);
    if (!framing_error || data_valid) begin
        $display("FAIL: bad stop bit should set framing_error without data");
        $finish;
    end

    drive_uart_frame(8'h12, 1'b1);
    drive_uart_frame(8'h34, 1'b1);
    if (!data_valid || data_out !== 8'h12 || !overrun) begin
        $display("FAIL: overrun should preserve 12 and set the sticky flag");
        $finish;
    end

    @(negedge clk);
    clear_overrun = 1'b1;
    @(negedge clk);
    clear_overrun = 1'b0;
    if (overrun || !framing_error) begin
        $display("FAIL: overrun clear should not clear framing_error");
        $finish;
    end

    @(negedge clk);
    clear_framing_error = 1'b1;
    @(negedge clk);
    clear_framing_error = 1'b0;
    if (framing_error) begin
        $display("FAIL: framing_error did not clear");
        $finish;
    end

    $display("PASS: uart_rx data, framing, and overrun behavior");
    $finish;
end

endmodule
