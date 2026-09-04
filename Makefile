# gowin-lm1881-clone
RTL      = rtl/sync_separator.v
SIM_OUT  = sim/out

.PHONY: sim clean
sim: $(SIM_OUT)/tb_sync_separator.vvp
	vvp -n $< | grep -v '^VCD'

$(SIM_OUT)/tb_sync_separator.vvp: $(RTL) sim/tb_sync_separator.v
	@mkdir -p $(SIM_OUT)
	iverilog -g2012 -o $@ $^

clean:
	rm -rf $(SIM_OUT) impl build

# ---- GOWIN EDA (macOS: /Applications/GowinIDE.app) ----
GW_SH = ./gowin/gw_sh.sh
FS    = impl/pnr/lm1881_clone.fs

.PHONY: build flash flash-sram
build:
	$(GW_SH) gowin/build.tcl

flash-sram: $(FS)       # SRAM に一時書き込み (電源断で消える)
	openFPGALoader -b tangnano9k $(FS)

flash: $(FS)            # 内蔵 Flash に書き込み
	openFPGALoader -b tangnano9k -f $(FS)

# HDMI 画面を 1 フレーム シミュレーションで描画 → sim/out/frame.png (要 Pillow)
HDMI_RTL = rtl/sync_separator.v rtl/hdmi/tmds_encoder.v rtl/hdmi/hdmi_tx.v rtl/hdmi/font5x7.v \
           rtl/hdmi/screen_text.v rtl/hdmi/bin2bcd16.v rtl/hdmi/status_display.v
.PHONY: sim-display gen
sim-display: $(HDMI_RTL) sim/gowin_stubs.v sim/tb_display.v
	@mkdir -p $(SIM_OUT)
	iverilog -g2012 -o $(SIM_OUT)/tb_display.vvp sim/gowin_stubs.v $(HDMI_RTL) sim/tb_display.v
	vvp -n $(SIM_OUT)/tb_display.vvp
	python3 -c "from PIL import Image; Image.open('$(SIM_OUT)/frame.ppm').save('$(SIM_OUT)/frame.png')"

gen:    # フォント ROM / 画面テキストを再生成
	python3 tools/gen_font.py
	python3 tools/gen_screen.py
