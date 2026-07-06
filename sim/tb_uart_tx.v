`timescale 1ns/1ps

module tb_uart_tx;

reg clk;
reg reset;
reg valid;
reg [7:0] data_in;

wire ready;
wire txd;

localparam integer BIT_CLKS = 10;

uart_tx #(
    .CLK_FREQ(100),
    .BAUD(10)
) dut (
    .clk(clk),
    .reset(reset),
    .valid(valid),
    .data_in(data_in),
    .ready(ready),
    .txd(txd)
);

always #5 clk = ~clk;

task sample_bit;
    output bit_value;
    begin
        #(BIT_CLKS * 10);
        bit_value = txd;
    end
endtask

reg sampled;

initial begin
    clk = 1'b0;
    reset = 1'b1;
    valid = 1'b0;
    data_in = 8'h00;
    sampled = 1'b1;

    $dumpfile("sim/build/tb_uart_tx.vcd");
    $dumpvars(0, tb_uart_tx);

    #30;
    reset = 1'b0;
    @(posedge clk);
    data_in = 8'h41;
    valid = 1'b1;
    @(posedge clk);
    valid = 1'b0;

    #(BIT_CLKS * 10 / 2);
    if (txd !== 1'b0) begin
        $display("FAIL: 没有观察到起始位");
        $finish;
    end

    sample_bit(sampled);
    if (sampled !== 1'b1) begin
        $display("FAIL: bit0 期望为 1");
        $finish;
    end

    sample_bit(sampled);
    if (sampled !== 1'b0) begin
        $display("FAIL: bit1 期望为 0");
        $finish;
    end

    wait (ready === 1'b1);
    #20;
    if (txd !== 1'b1) begin
        $display("FAIL: 停止位/空闲电平应为高");
        $finish;
    end

    $display("PASS: uart_tx 一帧发送完成");
    $finish;
end

endmodule
