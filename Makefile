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
