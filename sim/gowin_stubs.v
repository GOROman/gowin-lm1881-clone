// iverilog 用 GOWIN プリミティブの簡易スタブ (機能は最低限)
`timescale 1ns/1ps
module OSER10 #(parameter GSREN="false", LSREN="true") (output reg Q, input D0,D1,D2,D3,D4,D5,D6,D7,D8,D9, input PCLK, FCLK, RESET);
    reg [9:0] sh; reg [3:0] n = 0;
    always @(posedge PCLK) sh <= {D9,D8,D7,D6,D5,D4,D3,D2,D1,D0};
    always @(posedge FCLK or negedge FCLK) begin Q <= sh[n]; n <= (n == 9) ? 0 : n + 1; end
endmodule
module TLVDS_OBUF (input I, output O, output OB); assign O = I; assign OB = ~I; endmodule
