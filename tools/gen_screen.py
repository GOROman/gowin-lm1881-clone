#!/usr/bin/env python3
"""画面の固定テキスト (40桁×30行) から rtl/hdmi/screen_text.v を生成する。"""
COLS, ROWS = 40, 30
T = {
 0: " LM1881 CLONE - TANG NANO 9K  SYNC SEP  ",
 2: " LOCK:[ ]  PLL:[ ]  FIELD:---   IN:[ ]  ",
 4: " LINES/FIELD:---  H:--.-us  SYNC:-.-us  ",
 5: " SLICE DUTY:---/255  (S1:HOLD S2:RST)   ",
 7: " H VIEW: 1 LINE = 76us  TRIG=HSYNC      ",
 8: "CS", 10: "HS", 12: "VS", 14: "BG",
16: " V VIEW: 6.4 LINES = 406us  TRIG=VSYNC  ",
17: "CS", 19: "HS", 21: "VS", 23: "BG",
26: " OUT 27=CS 28=HS 29=VS 30=BG 31=OE 32=LK ",
28: " GITHUB.COM/GOROMAN/GOWIN-LM1881-CLONE  ",
}
out = ["// 自動生成: tools/gen_screen.py -- 画面固定テキスト", "`default_nettype none",
       "module screen_text(input wire [5:0] col, input wire [4:0] row, output reg [7:0] ch);",
       "    always @* begin", "        ch = 8'h20;", "        case (row)"]
for r in range(ROWS):
    s = T.get(r, "").ljust(COLS)[:COLS]
    if s.strip() == "": continue
    out.append(f"            5'd{r}: case (col)")
    for c, chr_ in enumerate(s):
        if chr_ != " ":
            out.append(f"                6'd{c}: ch = 8'h{ord(chr_):02X}; // '{chr_}'")
    out.append("                default: ch = 8'h20;")
    out.append("            endcase")
out += ["            default: ch = 8'h20;", "        endcase", "    end", "endmodule", "`default_nettype wire"]
open("rtl/hdmi/screen_text.v", "w").write("\n".join(out) + "\n")
