// NTSC 同期を流しつつ HDMI 表示 1 フレームを PPM に書き出す (目視確認用)
`timescale 1ns/1ps
module tb_display;
    localparam real CLK_NS = 1000.0 / 25.2;
    localparam real H = 63555.6, H2 = H / 2.0;
    reg clk = 0, clk_ser = 0, rst_n = 0, vin = 1;
    always #(CLK_NS/2.0) clk = ~clk;
    always #(CLK_NS/10.0) clk_ser = ~clk_ser;

    wire csync_n, hsync_n, vsync_n, burst_n, odd_even, locked, pulse_stb;
    wire [15:0] line_period, h_width; wire [9:0] field_lines;
    sync_separator #(.CLK_HZ(25_200_000)) u_sep (.clk(clk), .rst_n(rst_n), .video_in(vin),
        .csync_n(csync_n), .hsync_n(hsync_n), .vsync_n(vsync_n), .burst_n(burst_n), .odd_even(odd_even), .locked(locked),
        .line_period(line_period), .h_width(h_width), .field_lines(field_lines), .pulse_stb(pulse_stb));
    wire [9:0] px, py; wire [23:0] rgb; wire de_ahead;
    wire tcp, tcn; wire [2:0] tdp, tdn;
    hdmi_tx u_hdmi (.clk_pix(clk), .clk_ser(clk_ser), .rst_n(rst_n), .x(px), .y(py), .de_ahead(de_ahead), .rgb(rgb),
        .tmds_clk_p(tcp), .tmds_clk_n(tcn), .tmds_d_p(tdp), .tmds_d_n(tdn));
    status_display u_disp (.clk(clk), .rst_n(rst_n), .x(px), .y(py), .rgb(rgb),
        .csync_n(csync_n), .hsync_n(hsync_n), .vsync_n(vsync_n), .burst_n(burst_n),
        .odd_even(odd_even), .locked(locked), .pll_lock(1'b1), .in_active(1'b1), .agc_hold(1'b0),
        .line_period(line_period), .h_width(h_width), .field_lines(field_lines), .duty(8'd42));

    task pulse(input real low_ns, input real total_ns); begin vin = 0; #(low_ns); vin = 1; #(total_ns - low_ns); end endtask
    task field1; begin repeat(6) pulse(2300,H2); repeat(6) pulse(H2-4700,H2); repeat(6) pulse(2300,H2); repeat(253) pulse(4700,H); pulse(4700,H2); end endtask
    task field2; begin repeat(6) pulse(2300,H2); repeat(6) pulse(H2-4700,H2); repeat(6) pulse(2300,H2); #(H2); repeat(253) pulse(4700,H); end endtask
    initial begin #200 rst_n = 1; forever begin field1; field2; end end

    // de_ahead の 2clk 後に rgb が有効
    reg [1:0] de_d; always @(posedge clk) de_d <= {de_d[0], de_ahead};
    integer fd, frame = 0, npx = 0;
    reg [9:0] py_d; always @(posedge clk) py_d <= py;
    initial begin
        fd = $fopen("sim/out/frame.ppm", "w");
        $fwrite(fd, "P6\n640 480\n255\n");
        // 3 フレーム目を書き出す (同期がロックして波形が溜まった後)
        wait (rst_n); 
        repeat (3) begin @(posedge clk); while (!(px == 0 && py == 0)) @(posedge clk); end
        while (!(px == 0 && py == 0 && npx > 0)) begin
            @(posedge clk);
            if (de_d[1]) begin $fwrite(fd, "%c%c%c", rgb[23:16], rgb[15:8], rgb[7:0]); npx = npx + 1; end
        end
        $fclose(fd);
        $display("wrote %0d pixels", npx);
        $finish;
    end
endmodule
