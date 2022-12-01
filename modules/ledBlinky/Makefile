MODULE_NAME = blinky
BUILD = ./out
HW := mercurial

SRC := $(wildcard ./src/*.v)

# Red color to print in console
RED := $(shell tput -Txterm setaf 1)
RESET := $(shell tput -Txterm sgr0)

ifeq ($(HW),breakout)
	PACKAGE = ct256
	HW = breakout
	PCF = breakout.pcf
else 
	PACKAGE = tq144:4k
	HW:= mercurial
	PCF = mercurial.pcf
endif

#all: syn pnr pack
all: syn pnr

show:
	@echo "${RED}source files: ${RESET}" $(SRC)

show-blocks: $(SRC)
	yosys -p "prep -top $(MODULE_NAME); write_json $(BUILD)/output.json" $(SRC)
	yosys -p "read_verilog $(SRC); show -format svg -prefix ./show"

syn: $(BUILD)/$(MODULE_NAME).json
	@echo "${RED}Ending synthesis.${RESET}"

pnr : $(BUILD)/$(MODULE_NAME).asc
	@echo "${RED}Ending place and route.${RESET}"


$(BUILD)/$(MODULE_NAME).blif $(BUILD)/$(MODULE_NAME).json: $(SRC)
	mkdir -p $(BUILD)
	yosys -p "read_verilog $(SRC); synth_ice40 -top $(MODULE_NAME) -blif $(BUILD)/$(MODULE_NAME).blif -json $(BUILD)/$(MODULE_NAME).json"

$(BUILD)/$(MODULE_NAME).asc: $(BUILD)/$(MODULE_NAME).json $(PCF)
	nextpnr-ice40 --hx8k --package $(PACKAGE) --pcf $(PCF) --json $(BUILD)/$(MODULE_NAME).json --asc $(BUILD)/$(MODULE_NAME).asc
