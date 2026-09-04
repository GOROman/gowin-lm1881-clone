// NTSC 同期波形 (525 本, インターレース, 等化/切り込みパルス入り) を生成して
// sync_separator の HSYNC 数 / VSYNC 幅 / ODD-EVEN / BURST タイミングを検証する。
`timescale 1ns/1ps
module tb_sync_separator;
    localparam real CLK_NS = 1000.0 / 25.2;          // 25.2 MHz
    localparam real H      = 63555.6;                // NTSC ライン周期 [ns]
    localparam real H2     = H / 2.0;

    reg clk = 0, rst_n = 0, vin = 1;
    always #(CLK_NS/2.0) clk = ~clk;

    wire csync_n, hsync_n, vsync_n, burst_n, odd_even, locked, pulse_stb;
    wire [15:0] line_period, h_width; wire [9:0] field_lines;

    sync_separator #(.CLK_HZ(25_200_000), .IN_ACTIVE_LOW(1)) dut (
        .clk(clk), .rst_n(rst_n), .video_in(vin),
        .csync_n(csync_n), .hsync_n(hsync_n), .vsync_n(vsync_n), .burst_n(burst_n),
        .odd_even(odd_even), .locked(locked),
        .line_period(line_period), .h_width(h_width), .field_lines(field_lines), .pulse_stb(pulse_stb));

    // ---- 波形生成 ----------------------------------------------------------
    task pulse(input real low_ns, input real total_ns);
        begin vin = 0; #(low_ns); vin = 1; #(total_ns - low_ns); end
    endtask
    task glitch; begin vin = 0; #100; vin = 1; end endtask   // 0.1us ノイズ

    task field1;  // 奇数フィールド: EQ 先頭がライン先頭
        integer i;
        begin
            repeat (6) pulse(2300, H2);
            repeat (6) pulse(H2 - 4700, H2);
            repeat (6) pulse(2300, H2);
            for (i = 0; i < 253; i = i + 1) begin
                pulse(4700, H);
                if (i == 100) begin #20000; glitch; #(H - 20000 - 100); end // ノイズ混入
            end
            pulse(4700, H2);
        end
    endtask
    task field2;  // 偶数フィールド: EQ 先頭が半ライン
        begin
            repeat (6) pulse(2300, H2);
            repeat (6) pulse(H2 - 4700, H2);
            repeat (6) pulse(2300, H2);
            #(H2);
            repeat (253) pulse(4700, H);
        end
    endtask

    // ---- 計測 --------------------------------------------------------------
    integer hs_cnt = 0, vs_cnt = 0, errors = 0;
    real    vs_fall_t, vs_len, hs_last_t, hs_period, b_fall_t, b_len, csync_rise_t;
    reg     oe_at_vs;

    always @(negedge hsync_n) begin hs_period = $realtime - hs_last_t; hs_last_t = $realtime; hs_cnt = hs_cnt + 1; end
    always @(posedge csync_n) csync_rise_t = $realtime;
    always @(negedge burst_n) b_fall_t = $realtime;
    always @(posedge burst_n) b_len = $realtime - b_fall_t;
    always @(negedge vsync_n) begin
        vs_fall_t = $realtime; oe_at_vs = odd_even;
    end
    always @(posedge vsync_n) if (rst_n) begin
        vs_len = $realtime - vs_fall_t;
        vs_cnt = vs_cnt + 1;
        $display("[%0t] VSYNC#%0d len=%.1fus odd_even=%0d field_lines=%0d hsync_in_field=%0d line_period=%0dclk h_width=%0dclk locked=%0d",
                 $realtime, vs_cnt, vs_len/1000.0, oe_at_vs, field_lines, hs_cnt, line_period, h_width, locked);
        // 期待値: VSYNC 幅 ≈ 2.5H + 7us (最初の BROAD 後縁 〜 最初の EQ 後縁)
        if (vs_len < 2.4*H || vs_len > 2.8*H) begin errors = errors + 1; $display("  ERROR: vsync width"); end
        if (vs_cnt >= 3) begin
            // 2 フィールド目以降はライン数が 262/263 のどちらか
            if (field_lines != 262 && field_lines != 263) begin errors = errors + 1; $display("  ERROR: field_lines"); end
            // field_lines は「直前の VSYNC 開始〜今回の VSYNC 開始」の HSYNC 数。奇数開始時 263 / 偶数開始時 262 で交互になる
            if (oe_at_vs == 1 && field_lines != 263) begin errors = errors + 1; $display("  ERROR: odd field start should follow 263-line interval"); end
            if (oe_at_vs == 0 && field_lines != 262) begin errors = errors + 1; $display("  ERROR: even field start should follow 262-line interval"); end
        end
        hs_cnt = 0;
    end

    // バーストゲート: CSYNC 立上り (同期後縁) から 0.6us 後に 2.5us
    always @(posedge burst_n) if (rst_n) begin
        if (b_fall_t - csync_rise_t < 500 || b_fall_t - csync_rise_t > 800 || b_len < 2300 || b_len > 2700) begin
            errors = errors + 1; $display("[%0t] ERROR: burst dly=%.0fns len=%.0fns", $realtime, b_fall_t - csync_rise_t, b_len);
        end
    end

    initial begin
        $dumpfile("sim/out/tb_sync_separator.vcd"); $dumpvars(0, tb_sync_separator);
        #200 rst_n = 1;
        #(3*H);
        repeat (3) begin field1; field2; end
        #(2*H);
        if (!locked) begin errors = errors + 1; $display("ERROR: not locked"); end
        // 入力喪失でロック解除されること
        vin = 1; #60_000_000;
        if (locked) begin errors = errors + 1; $display("ERROR: still locked after signal loss"); end
        if (vs_cnt != 6) begin errors = errors + 1; $display("ERROR: vs_cnt=%0d", vs_cnt); end
        if (errors == 0) $display("PASS"); else $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
