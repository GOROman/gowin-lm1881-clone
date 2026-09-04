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
