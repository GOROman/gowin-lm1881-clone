// ============================================================================
// sync_separator.v  --  LM1881 風ビデオ同期分離器 (Verilog-2001)
//
//  入力 : 比較器で 2 値化したコンポジットビデオ (同期チップ = L が既定)
//  出力 : csync_n / hsync_n / vsync_n / burst_n / odd_even / locked
//
//  動作原理 (すべて時間幅ベース。NTSC / PAL 共通で動く):
//    * 入力を 2 段 FF で同期化 → グリッチフィルタ (T_GLITCH 以上安定で採用)
//    * 同期パルスの L 幅を測って分類
//        ~2.3us : 等化パルス (EQ)
//        ~4.7us : 水平同期 (H)
//        ~27us  : 切り込みパルス (BROAD, 垂直同期期間)
//    * HSYNC : パルス先頭のうち、前回 HSYNC から 3/4 ライン以上空いたものだけ採用
//              (半ライン間隔の EQ / BROAD 2 発目を除去)
//    * VSYNC : 最初の BROAD 検出で L、BROAD でないパルスが来たら H (NTSC で 3H)
//    * ODD/EVEN : 最初の BROAD の先頭が「ライン先頭」なら奇数、「半ライン」なら偶数
//    * BURST : H / EQ の後縁 (同期チップ終端) から T_BURST_DLY 後に T_BURST_W だけ L
// ============================================================================
`default_nettype none
module sync_separator #(
    parameter integer CLK_HZ        = 25_200_000,
    parameter         IN_ACTIVE_LOW = 1          // 1: 同期チップで video_in = 0
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        video_in,

    output reg         csync_n,      // 複合同期 (負論理)
    output reg         hsync_n,      // 水平同期 (負論理, 固定幅)
    output reg         vsync_n,      // 垂直同期 (負論理)
    output reg         burst_n,      // バーストゲート (負論理)
    output reg         odd_even,     // 1 = 奇数フィールド
    output reg         locked,       // 垂直同期を定期的に検出している

    // 診断用
    output reg  [15:0] line_period,  // 直近の H 周期 [clk]
    output reg  [15:0] h_width,      // 直近の H パルス幅 [clk]
    output reg  [9:0]  field_lines,  // 前フィールドのライン数 (262/263, 312/313)
    output reg         pulse_stb     // 何らかの同期パルス後縁で 1clk
);
    // ---- 時間定数 (0.1us 単位 → clk 数) -----------------------------------
    function integer us10; input integer x; begin us10 = ((CLK_HZ / 1000) * x) / 10000; end endfunction
    localparam integer T_GLITCH    = us10(3);     // 0.3 us
    localparam integer T_EQ_MAX    = us10(35);    // < 3.5 us : EQ
    localparam integer T_H_MAX     = us10(70);    // < 7.0 us : H
    localparam integer T_BROAD_MAX = us10(400);   // < 40 us  : BROAD, 以上は入力喪失
    localparam integer T_LINE      = us10(635);   // 63.5 us (NTSC 公称, PAL 64 us も可)
    localparam integer T_LINE_MIN  = (T_LINE * 3) / 4;
    localparam integer T_LINE_Q    = T_LINE / 4;
    localparam integer T_HSYNC_W   = us10(47);    // 4.7 us
    localparam integer T_BURST_DLY = us10(6);     // 0.6 us
    localparam integer T_BURST_W   = us10(25);    // 2.5 us
    localparam integer T_LOCK_TO   = CLK_HZ / 20; // 50 ms 垂直同期なしでロック解除

    // ---- 入力同期化 + グリッチフィルタ -------------------------------------
    reg [1:0] in_sync;
    always @(posedge clk) in_sync <= {in_sync[0], video_in};
    wire in_raw = IN_ACTIVE_LOW ? ~in_sync[1] : in_sync[1]; // 1 = 同期チップ

    reg        s_act;        // フィルタ後 (1 = 同期チップ)
    reg [7:0]  glitch_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_act <= 1'b0; glitch_cnt <= 8'd0;
        end else if (in_raw == s_act) begin
            glitch_cnt <= 8'd0;
        end else if (glitch_cnt >= T_GLITCH - 1) begin
            s_act <= in_raw; glitch_cnt <= 8'd0;
        end else begin
            glitch_cnt <= glitch_cnt + 8'd1;
        end
    end

    reg s_act_d;
    always @(posedge clk) s_act_d <= s_act;
    wire lead  =  s_act & ~s_act_d;   // 同期チップ先頭
    wire trail = ~s_act &  s_act_d;   // 同期チップ後縁

    // ---- パルス幅測定 ---------------------------------------------------------
    reg [15:0] width_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          width_cnt <= 16'd0;
        else if (lead)       width_cnt <= 16'd1;
        else if (s_act && width_cnt != 16'hFFFF) width_cnt <= width_cnt + 16'd1;
    end
    wire is_eq    = trail && (width_cnt <  T_EQ_MAX);
    wire is_h     = trail && (width_cnt >= T_EQ_MAX)  && (width_cnt < T_H_MAX);
    wire is_broad = trail && (width_cnt >= T_H_MAX)   && (width_cnt < T_BROAD_MAX);

    // ---- HSYNC (ライン先頭判定) ----------------------------------------------
    reg  in_vs;
    wire vs_start = is_broad && !in_vs;
    wire vs_end   = in_vs && trail && !is_broad;
    reg [15:0] since_h;       // 前回 HSYNC 先頭からの clk 数
    reg [15:0] lead_phase;    // 直近パルス先頭時点の since_h (フィールド判定用)
    reg [15:0] hsync_cnt;
    reg [9:0]  line_cnt;
    wire h_accept = lead && (since_h >= T_LINE_MIN);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            since_h <= 16'hFFFF; lead_phase <= 16'd0; line_period <= 16'd0;
            hsync_n <= 1'b1; hsync_cnt <= 16'd0; line_cnt <= 10'd0;
        end else begin
            if (lead) lead_phase <= since_h;
            if (h_accept) begin
                line_period <= since_h;
                since_h     <= 16'd1;
                hsync_n     <= 1'b0;
                hsync_cnt   <= 16'd1;
                line_cnt    <= line_cnt + 10'd1;
            end else begin
                if (since_h != 16'hFFFF) since_h <= since_h + 16'd1;
                if (!hsync_n) begin
                    if (hsync_cnt >= T_HSYNC_W) hsync_n <= 1'b1;
                    else hsync_cnt <= hsync_cnt + 16'd1;
                end
            end
            if (vs_start) line_cnt <= 10'd0;
        end
    end

    // ---- VSYNC / ODD-EVEN ------------------------------------------------------
    wire phase_is_line_start = (lead_phase < T_LINE_Q) || (lead_phase > (T_LINE - T_LINE_Q));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_vs <= 1'b0; vsync_n <= 1'b1; odd_even <= 1'b0; field_lines <= 10'd0;
        end else begin
            if (vs_start) begin
                in_vs       <= 1'b1;
                vsync_n     <= 1'b0;
                odd_even    <= phase_is_line_start;
                field_lines <= line_cnt;
            end else if (vs_end) begin
                in_vs   <= 1'b0;
                vsync_n <= 1'b1;
            end
        end
    end

    // ---- BURST ゲート ---------------------------------------------------------
    reg [15:0] burst_cnt;
    reg        burst_arm;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            burst_n <= 1'b1; burst_cnt <= 16'd0; burst_arm <= 1'b0;
        end else if (is_h || is_eq) begin
            burst_arm <= 1'b1; burst_cnt <= 16'd0; burst_n <= 1'b1;
        end else if (burst_arm) begin
            burst_cnt <= burst_cnt + 16'd1;
            if (burst_cnt == T_BURST_DLY - 1)                 burst_n <= 1'b0;
            if (burst_cnt == T_BURST_DLY + T_BURST_W - 1) begin burst_n <= 1'b1; burst_arm <= 1'b0; end
        end
    end

    // ---- CSYNC / LOCK / 診断 ---------------------------------------------------
    reg [31:0] lock_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            csync_n <= 1'b1; locked <= 1'b0; lock_cnt <= 32'd0;
            h_width <= 16'd0; pulse_stb <= 1'b0;
        end else begin
            csync_n   <= ~s_act;
            pulse_stb <= trail;
            if (is_h) h_width <= width_cnt;
            if (vs_start) begin
                locked <= 1'b1; lock_cnt <= 32'd0;
            end else if (lock_cnt >= T_LOCK_TO) begin
                locked <= 1'b0;
            end else begin
                lock_cnt <= lock_cnt + 32'd1;
            end
        end
    end
endmodule
`default_nettype wire
