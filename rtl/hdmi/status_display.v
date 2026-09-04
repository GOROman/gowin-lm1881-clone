// ============================================================================
// status_display.v -- 同期分離の状態を 640x480 に描画する (テキスト + 波形)
//   hdmi_tx から (x,y) を受け、2clk 後に rgb を返す
// ============================================================================
`default_nettype none
module status_display #(
    parameter integer CLK_HZ = 25_200_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    output reg  [23:0] rgb,

    // 同期分離器の状態
    input  wire        csync_n, hsync_n, vsync_n, burst_n,
    input  wire        odd_even, locked, pll_lock, in_active, agc_hold,
    input  wire [15:0] line_period,
    input  wire [15:0] h_width,
    input  wire [9:0]  field_lines,
    input  wire [7:0]  duty
);
    // ------------------------------------------------------------------
    // 波形キャプチャ: H ビュー (3clk/px, HSYNC トリガ) / V ビュー (16clk/px, VSYNC トリガ)
    // 各 640 サンプル × 4bit {burst_n, vsync_n, hsync_n, csync_n}。表示フレームごとに 1 回再アーム。
    // ------------------------------------------------------------------
    localparam H_DECIM = 3, V_DECIM = 16;
    wire [3:0] sig = {burst_n, vsync_n, hsync_n, csync_n};
    wire frame_start = (x == 10'd0) && (y == 10'd0);

    reg hs_d, vs_d;
    always @(posedge clk) begin hs_d <= hsync_n; vs_d <= vsync_n; end
    wire hs_fall = hs_d & ~hsync_n;
    wire vs_fall = vs_d & ~vsync_n;

    reg [3:0] mem_h [0:639];
    reg [3:0] mem_v [0:639];
    reg        arm_h, run_h, arm_v, run_v;
    reg [9:0]  wa_h, wa_v;
    reg [4:0]  dec_h, dec_v;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arm_h <= 1'b1; run_h <= 1'b0; wa_h <= 10'd0; dec_h <= 5'd0;
            arm_v <= 1'b1; run_v <= 1'b0; wa_v <= 10'd0; dec_v <= 5'd0;
        end else begin
            if (frame_start) begin arm_h <= 1'b1; arm_v <= 1'b1; end
            // H
            if (arm_h && hs_fall) begin run_h <= 1'b1; arm_h <= 1'b0; wa_h <= 10'd0; dec_h <= 5'd0; end
            else if (run_h) begin
                if (dec_h == H_DECIM - 1) begin
                    dec_h <= 5'd0; wa_h <= wa_h + 10'd1;
                    if (wa_h == 10'd639) run_h <= 1'b0;
                end else dec_h <= dec_h + 5'd1;
            end
            // V
            if (arm_v && vs_fall) begin run_v <= 1'b1; arm_v <= 1'b0; wa_v <= 10'd0; dec_v <= 5'd0; end
            else if (run_v) begin
                if (dec_v == V_DECIM - 1) begin
                    dec_v <= 5'd0; wa_v <= wa_v + 10'd1;
                    if (wa_v == 10'd639) run_v <= 1'b0;
                end else dec_v <= dec_v + 5'd1;
            end
        end
    end
    always @(posedge clk) begin
        if (run_h && dec_h == 0) mem_h[wa_h] <= sig;
        if (run_v && dec_v == 0) mem_v[wa_v] <= sig;
    end

    // ------------------------------------------------------------------
    // 数値 → BCD (フレーム先頭で変換)
    // us*10 = clk * 10 / 25.2 = clk * 1626 >> 12  (CLK_HZ=25.2MHz 前提; 他周波数は係数を変える)
    // ------------------------------------------------------------------
    localparam integer US10_MUL = (4096 * 10 * 100) / (CLK_HZ / 10000); // 1625 @25.2MHz (32bit オーバーフロー回避)
    wire [27:0] h_us10_w  = (line_period * US10_MUL) >> 12;
    wire [27:0] s_us10_w  = (h_width     * US10_MUL) >> 12;
    wire [15:0] bcd_lines, bcd_hus, bcd_sus, bcd_duty;
    bin2bcd16 b0 (.clk(clk), .start(frame_start), .bin({6'd0, field_lines}), .bcd(bcd_lines), .done());
    bin2bcd16 b1 (.clk(clk), .start(frame_start), .bin(h_us10_w[15:0]),      .bcd(bcd_hus),   .done());
    bin2bcd16 b2 (.clk(clk), .start(frame_start), .bin(s_us10_w[15:0]),      .bcd(bcd_sus),   .done());
    bin2bcd16 b3 (.clk(clk), .start(frame_start), .bin({8'd0, duty}),        .bcd(bcd_duty),  .done());

    // ------------------------------------------------------------------
    // ステージ 0: 文字/フォント/RAM 読み出し
    // ------------------------------------------------------------------
    wire [5:0] col = x[9:4];
    wire [4:0] row = y[9:4];
    wire [3:0] cx  = x[3:0];
    wire [3:0] cy  = y[3:0];

    wire [7:0] ch_static;
    screen_text u_txt (.col(col), .row(row), .ch(ch_static));

    function [7:0] dig; input [3:0] d; begin dig = 8'h30 + {4'd0, d}; end endfunction
    reg [7:0] ch;
    always @* begin
        ch = ch_static;
        // 行 2: LOCK:[ ] PLL:[ ] FIELD:--- IN:[ ]
        if (row == 5'd2) begin
            if (col == 6'd7)  ch = locked    ? 8'h2A : 8'h20;
            if (col == 6'd16) ch = pll_lock  ? 8'h2A : 8'h20;
            if (col == 6'd26) ch = odd_even  ? 8'h4F : 8'h45;   // O / E
            if (col == 6'd27) ch = odd_even  ? 8'h44 : 8'h56;   // D / V
            if (col == 6'd28) ch = odd_even  ? 8'h44 : 8'h4E;   // D / N
            if (col == 6'd36) ch = in_active ? 8'h2A : 8'h20;
        end
        // 行 4: LINES/FIELD:ddd  H:dd.dus  SYNC:d.dus
        if (row == 5'd4) begin
            if (col == 6'd13) ch = dig(bcd_lines[11:8]);
            if (col == 6'd14) ch = dig(bcd_lines[7:4]);
            if (col == 6'd15) ch = dig(bcd_lines[3:0]);
            if (col == 6'd20) ch = dig(bcd_hus[11:8]);
            if (col == 6'd21) ch = dig(bcd_hus[7:4]);
            if (col == 6'd23) ch = dig(bcd_hus[3:0]);
            if (col == 6'd33) ch = dig(bcd_sus[7:4]);
            if (col == 6'd35) ch = dig(bcd_sus[3:0]);
        end
        // 行 5: SLICE DUTY:ddd
        if (row == 5'd5) begin
            if (col == 6'd12) ch = dig(bcd_duty[11:8]);
            if (col == 6'd13) ch = dig(bcd_duty[7:4]);
            if (col == 6'd14) ch = dig(bcd_duty[3:0]);
            if (col == 6'd21) ch = agc_hold ? 8'h2A : 8'h28;   // HOLD 中は '*'
        end
    end

    // フォント: 5x7 を 2 倍 → セル内 x 2..11, y 1..14
    wire [2:0] frow = (cy - 4'd1) >> 1;
    wire [4:0] fbits;
    font5x7 u_font (.ch(ch), .row(frow), .bits(fbits));
    wire in_glyph = (cy >= 4'd1) && (cy <= 4'd14) && (cx >= 4'd2) && (cx <= 4'd11);
    wire [2:0] fcol = (cx - 4'd2) >> 1;
    wire text_px = in_glyph && fbits[4 - fcol];

    // 波形領域
    localparam TR_X0 = 48;
    localparam H_Y0  = 128, V_Y0 = 272;     // 各 4ch × 32px
    wire in_h_area = (y >= H_Y0) && (y < H_Y0 + 128) && (x >= TR_X0) && (x < 640);
    wire in_v_area = (y >= V_Y0) && (y < V_Y0 + 128) && (x >= TR_X0) && (x < 640);
    wire [9:0] ra = x - TR_X0;
    reg  [3:0] q_h, q_v;
    always @(posedge clk) begin q_h <= mem_h[ra]; q_v <= mem_v[ra]; end

    // ステージ 0 → 1 レジスタ
    reg        s1_text, s1_h, s1_v, s1_row_hdr;
    reg [6:0]  s1_ly;          // 領域内の y (0..127)
    reg [3:0]  s1_qh_p, s1_qv_p;
    reg        s1_first;
    always @(posedge clk) begin
        s1_text <= text_px;
        s1_h    <= in_h_area;
        s1_v    <= in_v_area;
        s1_ly   <= in_h_area ? (y - H_Y0) : (y - V_Y0);
        s1_qh_p <= q_h; s1_qv_p <= q_v;   // 1 サンプル前 (次段で prev として使う)
        s1_first <= (x == TR_X0);
        s1_row_hdr <= (row == 5'd0);
    end

    // ステージ 1 → 2: 描画
    wire [1:0] chn = s1_ly[6:5];
    wire [4:0] ly  = s1_ly[4:0];
    wire [3:0] cur  = s1_h ? q_h : q_v;              // q_* は今 s1 と同じサンプル (ra は 1clk 遅れ読み)
    wire [3:0] prv  = s1_h ? s1_qh_p : s1_qv_p;
    wire bit_c = cur[chn];
    wire bit_p = s1_first ? bit_c : prv[chn];
    wire lvl_px = bit_c ? (ly >= 5'd6 && ly < 5'd8) : (ly >= 5'd22 && ly < 5'd24);
    wire edge_px = (bit_c != bit_p) && (ly >= 5'd6 && ly < 5'd24);
    wire trace_px = (s1_h | s1_v) && (lvl_px | edge_px);
    wire grid_px  = (s1_h | s1_v) && (ly == 5'd31);

    reg [23:0] trace_col;
    always @* case (chn)
        2'd0: trace_col = 24'hFFD000;   // CS 黄
        2'd1: trace_col = 24'h40E0FF;   // HS シアン
        2'd2: trace_col = 24'hFF60E0;   // VS マゼンタ
        default: trace_col = 24'h60FF80; // BG 緑
    endcase

    always @(posedge clk) begin
        if (trace_px)        rgb <= trace_col;
        else if (s1_text)    rgb <= s1_row_hdr ? 24'hFFFFFF : 24'hE0E0E0;
        else if (grid_px)    rgb <= 24'h303848;
        else if (s1_row_hdr) rgb <= 24'h204080;
        else                 rgb <= 24'h101418;
    end
endmodule
`default_nettype wire
