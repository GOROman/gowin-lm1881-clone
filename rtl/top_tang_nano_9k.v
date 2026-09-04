// ============================================================================
// top_tang_nano_9k.v -- Tang Nano 9K 用トップ
//   27 MHz → rPLL 126 MHz → CLKDIV/5 → 25.2 MHz (HDMI ピクセルクロックと共用)
// ============================================================================
`default_nettype none
module top_tang_nano_9k (
    input  wire       clk_27m,
    input  wire       key_s1_n,     // 押すと AGC 停止 (duty 固定)
    input  wire       key_s2_n,     // 押すとリセット
    input  wire       video_in,     // 比較器出力 (同期チップで L)

    output wire       slice_pwm,    // RC で平滑して比較器の基準電圧に
    output wire       csync_n,
    output wire       hsync_n,
    output wire       vsync_n,
    output wire       burst_n,
    output wire       odd_even,
    output wire       locked,
    output wire [5:0] led_n         // アクティブ L
);
    // ---- クロック ---------------------------------------------------------
    wire clk_ser, pll_lock, clk_pix;
    rPLL #(
        .FCLKIN("27"), .IDIV_SEL(2), .FBDIV_SEL(13), .ODIV_SEL(4),
        .DEVICE("GW1NR-9C"), .DYN_IDIV_SEL("false"), .DYN_FBDIV_SEL("false"),
        .DYN_ODIV_SEL("false"), .PSDA_SEL("0000"), .DYN_DA_EN("true"),
        .DUTYDA_SEL("1000"), .CLKOUT_FT_DIR(1'b1), .CLKOUTP_FT_DIR(1'b1),
        .CLKOUT_DLY_STEP(0), .CLKOUTP_DLY_STEP(0), .CLKFB_SEL("internal"),
        .CLKOUT_BYPASS("false"), .CLKOUTP_BYPASS("false"), .CLKOUTD_BYPASS("false"),
        .DYN_SDIV_SEL(2), .CLKOUTD_SRC("CLKOUT"), .CLKOUTD3_SRC("CLKOUT")
    ) u_pll (
        .CLKOUT(clk_ser), .LOCK(pll_lock), .CLKOUTP(), .CLKOUTD(), .CLKOUTD3(),
        .RESET(1'b0), .RESET_P(1'b0), .CLKIN(clk_27m), .CLKFB(1'b0),
        .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0)
    );
    CLKDIV #(.DIV_MODE("5"), .GSREN("false")) u_div (
        .CLKOUT(clk_pix), .HCLKIN(clk_ser), .RESETN(pll_lock), .CALIB(1'b1));

    // ---- リセット ---------------------------------------------------------
    reg [3:0] rst_sr = 4'd0;
    always @(posedge clk_pix or negedge key_s2_n)
        if (!key_s2_n) rst_sr <= 4'd0; else rst_sr <= {rst_sr[2:0], pll_lock};
    wire rst_n = rst_sr[3];

    // ---- 同期分離 ---------------------------------------------------------
    wire [15:0] line_period, h_width;
    wire [9:0]  field_lines;
    wire        pulse_stb;
    sync_separator #(.CLK_HZ(25_200_000), .IN_ACTIVE_LOW(1)) u_sep (
        .clk(clk_pix), .rst_n(rst_n), .video_in(video_in),
        .csync_n(csync_n), .hsync_n(hsync_n), .vsync_n(vsync_n), .burst_n(burst_n),
        .odd_even(odd_even), .locked(locked),
        .line_period(line_period), .h_width(h_width), .field_lines(field_lines), .pulse_stb(pulse_stb));

    // ---- スライスレベル AGC ---------------------------------------------------
    wire [7:0] duty;
    slice_agc #(.CLK_HZ(25_200_000)) u_agc (
        .clk(clk_pix), .rst_n(rst_n), .hold(~key_s1_n), .locked(locked),
        .pulse_stb(pulse_stb), .h_width(h_width), .slice_pwm(slice_pwm), .duty(duty));

    // ---- LED ------------------------------------------------------------------
    // led0: locked, led1: odd_even, led2: vsync 点滅(フィールド), led3: PLL lock
    // led4: 入力に何かパルスがある, led5: AGC hold
    reg [23:0] act_cnt;
    always @(posedge clk_pix) act_cnt <= pulse_stb ? 24'hFFFFFF : (act_cnt != 0 ? act_cnt - 24'd1 : 24'd0);
    reg vs_tgl, vs_d;
    always @(posedge clk_pix) begin vs_d <= vsync_n; if (vs_d & ~vsync_n) vs_tgl <= ~vs_tgl; end
    assign led_n = ~{~key_s1_n, act_cnt != 0, pll_lock, vs_tgl, odd_even, locked};
endmodule
`default_nettype wire
