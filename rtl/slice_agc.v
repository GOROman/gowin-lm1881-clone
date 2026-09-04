// ============================================================================
// slice_agc.v -- 比較器のスライスレベル (基準電圧) を PWM DAC で生成し、
//                同期パルス幅が 4.7us になるよう自動追従する
//
//   外部回路:  slice_pwm ─ 10k ─┬─ 比較器 (-) 入力
//                              100nF
//                               ┴ GND
//   比較器 (+) には AC 結合 + 同期チップクランプしたコンポジット信号。
//   出力 = (video > ref) なので同期チップで L (IN_ACTIVE_LOW=1)。
//   ref を上げると L 幅が広がる → 広すぎたら duty を下げる。
//   ロックしていないときは duty をゆっくり掃引して同期を探す。
// ============================================================================
`default_nettype none
module slice_agc #(
    parameter integer CLK_HZ  = 25_200_000,
    parameter [7:0]   INIT    = 8'd40       // 初期 duty (0..255)
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       hold,        // 1: 追従停止 (duty 固定)
    input  wire       locked,
    input  wire       pulse_stb,   // sync_separator.pulse_stb
    input  wire [15:0] h_width,    // sync_separator.h_width
    output reg        slice_pwm,
    output reg  [7:0] duty
);
    function integer us10; input integer x; begin us10 = ((CLK_HZ / 1000) * x) / 10000; end endfunction
    localparam integer W_LO = us10(40);   // 4.0 us 未満 → 狭すぎ → duty up
    localparam integer W_HI = us10(55);   // 5.5 us 超   → 広すぎ → duty down
    localparam integer T_SWEEP = CLK_HZ / 1000;  // 非ロック時は 1ms ごとに +1

    // ---- PWM (8bit, ~98kHz @25.2MHz) ----
    reg [7:0] pwm_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin pwm_cnt <= 8'd0; slice_pwm <= 1'b0; end
        else begin pwm_cnt <= pwm_cnt + 8'd1; slice_pwm <= (pwm_cnt < duty); end
    end

    // ---- 追従 ----
    reg [5:0]  pulse_cnt;   // 64 パルスごとに 1 LSB 動かす
    reg [31:0] sweep_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            duty <= INIT; pulse_cnt <= 6'd0; sweep_cnt <= 32'd0;
        end else if (hold) begin
            sweep_cnt <= 32'd0;
        end else if (locked) begin
            sweep_cnt <= 32'd0;
            if (pulse_stb) begin
                pulse_cnt <= pulse_cnt + 6'd1;
                if (&pulse_cnt) begin
                    if      (h_width > W_HI && duty != 8'd0)   duty <= duty - 8'd1;
                    else if (h_width < W_LO && duty != 8'd255) duty <= duty + 8'd1;
                end
            end
        end else begin
            if (sweep_cnt >= T_SWEEP) begin sweep_cnt <= 32'd0; duty <= duty + 8'd1; end
            else sweep_cnt <= sweep_cnt + 32'd1;
        end
    end
endmodule
`default_nettype wire
