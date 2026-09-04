// 16bit → 4桁 BCD (double dabble, 逐次 16clk)
`default_nettype none
module bin2bcd16 (
    input  wire        clk,
    input  wire        start,
    input  wire [15:0] bin,
    output reg  [15:0] bcd,     // {d3,d2,d1,d0}
    output reg         done
);
    reg [15:0] sh; reg [15:0] acc; reg [4:0] n; reg busy;
    wire [3:0] a0 = acc[3:0]  > 4 ? acc[3:0]  + 4'd3 : acc[3:0];
    wire [3:0] a1 = acc[7:4]  > 4 ? acc[7:4]  + 4'd3 : acc[7:4];
    wire [3:0] a2 = acc[11:8] > 4 ? acc[11:8] + 4'd3 : acc[11:8];
    wire [3:0] a3 = acc[15:12]> 4 ? acc[15:12]+ 4'd3 : acc[15:12];
    always @(posedge clk) begin
        done <= 1'b0;
        if (start) begin sh <= bin; acc <= 16'd0; n <= 5'd0; busy <= 1'b1; end
        else if (busy) begin
            acc <= {a3[2:0], a2, a1, a0, sh[15]};
            sh  <= {sh[14:0], 1'b0};
            n   <= n + 5'd1;
            if (n == 5'd15) begin busy <= 1'b0; done <= 1'b1; end
        end
        if (done) bcd <= acc;
    end
endmodule
`default_nettype wire
