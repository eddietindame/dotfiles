KB := bastardkb/charybdis/4x6
KM := eddie
QMK_DIR := $(HOME)/qmk_firmware
SRC_DIR := $(QMK_DIR)/keyboards/$(KB)/keymaps/$(KM)
FW := $(QMK_DIR)/bastardkb_charybdis_4x6_$(KM).uf2

.PHONY: compile flash sync clean

compile: sync
	cd $(QMK_DIR) && qmk compile -c -kb $(KB) -km $(KM) -e VIA_ENABLE=yes
	cp $(FW) .
	cp $(SRC_DIR)/config.h $(SRC_DIR)/keymap.c .

sync:
	@diff -q config.h $(SRC_DIR)/config.h > /dev/null 2>&1 || cp config.h $(SRC_DIR)/config.h
	@diff -q keymap.c $(SRC_DIR)/keymap.c > /dev/null 2>&1 || cp keymap.c $(SRC_DIR)/keymap.c

flash: compile
	@echo "Firmware ready: bastardkb_charybdis_4x6_$(KM).uf2"
	@echo "Enter bootloader (QK_BOOT or double-tap reset), then:"
	@echo "  cp bastardkb_charybdis_4x6_$(KM).uf2 /Volumes/RPI-RP2/"

clean:
	cd $(QMK_DIR) && qmk clean
