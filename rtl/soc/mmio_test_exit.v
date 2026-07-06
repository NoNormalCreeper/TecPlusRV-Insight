// 仿真专用的 test-exit MMIO 寄存器。
// firmware 写 TINYBUS_TEST_EXIT 后，testbench 可以用 exited/exit_code
// 判断程序已经跑到预期终点；真实上板时可以不接这个模块。
module mmio_test_exit (
    input        clk,
    input        reset,
    input        write_en,
    input  [31:0] write_data,
    output reg   exited,
    output reg [31:0] exit_code
);

always @(posedge clk) begin
    if (reset) begin
        exited <= 1'b0;
        exit_code <= 32'h0000_0000;
    end else if (write_en) begin
        // testbench 通过这个标志判断 PASS 或 FAIL。
        exited <= 1'b1;
        exit_code <= write_data;
    end
end

endmodule
