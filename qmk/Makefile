KB := bastardkb/charybdis/4x6
KM := eddie
QMK_DIR := $(HOME)/qmk_firmware
SRC_DIR := $(QMK_DIR)/keyboards/$(KB)/keymaps/$(KM)
FW := $(QMK_DIR)/bastardkb_charybdis_4x6_$(KM).uf2
PROFILES_DIR := profiles
ACTIVE := $(PROFILES_DIR)/.active

.PHONY: compile flash clean profiles use save active

# Get current profile name
CURRENT := $(shell cat $(ACTIVE) 2>/dev/null)

compile:
ifndef CURRENT
	@echo "No active profile. Run: make use P=profile-name"
	@echo ""; $(MAKE) --no-print-directory profiles
	@exit 1
endif
	cp $(PROFILES_DIR)/$(CURRENT)/config.h $(SRC_DIR)/config.h
	@test -f $(PROFILES_DIR)/$(CURRENT)/keymap.c && cp $(PROFILES_DIR)/$(CURRENT)/keymap.c $(SRC_DIR)/keymap.c || true
	cd $(QMK_DIR) && qmk compile -c -kb $(KB) -km $(KM) -e VIA_ENABLE=yes
	cp $(FW) .

flash: compile
	@echo "Firmware ready: bastardkb_charybdis_4x6_$(KM).uf2"
	@echo "Enter bootloader (QK_BOOT or double-tap reset), then:"
	@echo "  cp bastardkb_charybdis_4x6_$(KM).uf2 /Volumes/RPI-RP2/"

clean:
	cd $(QMK_DIR) && qmk clean

profiles:
	@echo "Available profiles:"
	@for d in $(PROFILES_DIR)/*/; do \
		name=$$(basename $$d); \
		if [ "$$name" = "$(CURRENT)" ]; then \
			echo "  $$name (active)"; \
		else \
			echo "  $$name"; \
		fi; \
	done

use:
ifndef P
	@echo "Usage: make use P=profile-name"
	@echo ""; $(MAKE) --no-print-directory profiles
else
	@test -d $(PROFILES_DIR)/$(P) || (echo "Profile '$(P)' not found" && exit 1)
	@echo $(P) > $(ACTIVE)
	@echo "Switched to profile: $(P)"
	$(MAKE) compile
endif

save:
ifndef P
	@echo "Usage: make save P=profile-name"
else
	mkdir -p $(PROFILES_DIR)/$(P)
	cp $(SRC_DIR)/config.h $(PROFILES_DIR)/$(P)/
	cp $(SRC_DIR)/keymap.c $(PROFILES_DIR)/$(P)/
	@echo $(P) > $(ACTIVE)
	@echo "Saved profile: $(P)"
endif

active:
	@if [ -n "$(CURRENT)" ]; then \
		echo "Active profile: $(CURRENT)"; \
		echo ""; cat $(PROFILES_DIR)/$(CURRENT)/config.h; \
	else \
		echo "No active profile"; \
	fi
