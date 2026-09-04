// 640x480@60 (25.2 MHz) DVI 出力。GOWIN OSER10 + ELVDS_OBUF でシリアライズ。
`default_nettype none
module hdmi_tx (
    input  wire       clk_pix,     // 25.2 MHz
    input  wire       clk_ser,     // 126 MHz
    input  wire       rst_n,
    // 表示側インタフェース (座標を出し、色を受け取る。色は 2clk 遅れて返す)
    output reg  [9:0] x,           // 0..799
    output reg  [9:0] y,           // 0..524
    output wire       de_ahead,    // x<640 && y<480 (座標と同じタイミング)
    input  wire [23:0] rgb,        // {r,g,b} : 座標の 2clk 後
    output wire       tmds_clk_p, tmds_clk_n,
    output wire [2:0] tmds_d_p, tmds_d_n
);
    localparam H_ACT = 640, H_FP = 16, H_SYNC = 96, H_TOT = 800;
    localparam V_ACT = 480, V_FP = 10, V_SYNC = 2,  V_TOT = 525;

    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) begin x <= 10'd0; y <= 10'd0; end
        else if (x == H_TOT - 1) begin
            x <= 10'd0;
            y <= (y == V_TOT - 1) ? 10'd0 : y + 10'd1;
        end else x <= x + 10'd1;
    end
    assign de_ahead = (x < H_ACT) && (y < V_ACT);
    wire hs_ahead = ~((x >= H_ACT + H_FP) && (x < H_ACT + H_FP + H_SYNC)); // 負極性
    wire vs_ahead = ~((y >= V_ACT + V_FP) && (y < V_ACT + V_FP + V_SYNC));

    // 色が 2clk 遅れて来るので同期信号も 2 段遅延
    reg [2:0] de_d, hs_d, vs_d;
    always @(posedge clk_pix) begin
        de_d <= {de_d[1:0], de_ahead}; hs_d <= {hs_d[1:0], hs_ahead}; vs_d <= {vs_d[1:0], vs_ahead};
    end
    wire de = de_d[1], hs = hs_d[1], vs = vs_d[1];

    wire [9:0] enc [0:2];
    tmds_encoder e0 (.clk(clk_pix), .de(de), .ctrl({vs, hs}), .d(rgb[7:0]),   .q(enc[0]));
    tmds_encoder e1 (.clk(clk_pix), .de(de), .ctrl(2'b00),    .d(rgb[15:8]),  .q(enc[1]));
    tmds_encoder e2 (.clk(clk_pix), .de(de), .ctrl(2'b00),    .d(rgb[23:16]), .q(enc[2]));

    wire [3:0] ser;
    genvar i;
    generate for (i = 0; i < 3; i = i + 1) begin : g_ser
        OSER10 #(.GSREN("false"), .LSREN("true")) u_oser (
            .Q(ser[i]), .PCLK(clk_pix), .FCLK(clk_ser), .RESET(~rst_n),
            .D0(enc[i][0]), .D1(enc[i][1]), .D2(enc[i][2]), .D3(enc[i][3]), .D4(enc[i][4]),
            .D5(enc[i][5]), .D6(enc[i][6]), .D7(enc[i][7]), .D8(enc[i][8]), .D9(enc[i][9]));
        ELVDS_OBUF u_buf (.I(ser[i]), .O(tmds_d_p[i]), .OB(tmds_d_n[i]));
    end endgenerate
    OSER10 #(.GSREN("false"), .LSREN("true")) u_oser_clk (
        .Q(ser[3]), .PCLK(clk_pix), .FCLK(clk_ser), .RESET(~rst_n),
        .D0(1'b1), .D1(1'b1), .D2(1'b1), .D3(1'b1), .D4(1'b1),
        .D5(1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0), .D9(1'b0));
    ELVDS_OBUF u_buf_clk (.I(ser[3]), .O(tmds_clk_p), .OB(tmds_clk_n));
endmodule
`default_nettype wire
