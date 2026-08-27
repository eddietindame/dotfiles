# Operational commands for this headless Mac mini.
# Targets are grouped: tailscale, health, remote access, dotfiles.
#
# Tailscale here is the open-source CLI + tailscaled LaunchDaemon, NOT the GUI
# app — only that variant starts before login. The CLI is not on the default
# PATH, hence the absolute path below.

TS     := /opt/homebrew/bin/tailscale
PEER   ?= 100.86.187.87
HOST   ?=

.DEFAULT_GOAL := help
.PHONY: help ts ts-up ts-down ts-ip ts-path ts-acl ts-net ts-web ts-web-off \
        ts-daemon health fv fv-on fv-off fv-restart fv-restart-in fv-arm \
        power-headless power-status terminfo mosh brew-sync

help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

## ---- tailscale ----------------------------------------------------------

ts: ## Peer list and connection state
	@$(TS) status

ts-ip: ## This machine's tailnet address
	@$(TS) ip -4

ts-up: ## Bring the tunnel up
	sudo $(TS) up

ts-down: ## Take the tunnel down
	sudo $(TS) down

ts-path: ## Is the peer link direct or DERP-relayed? (PEER=100.x.y.z)
	@$(TS) ping --c 3 $(PEER) 2>&1 | tail -1
	@$(TS) status 2>/dev/null | grep $(PEER) || echo "  peer not in status"

ts-acl: ## Which peers are permitted INBOUND to this machine
	@echo "Tailscale drops blocked packets silently — a missing entry here"
	@echo "looks like a hang, not a refusal:"
	@$(TS) debug netmap 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); s=sorted({x.split("/")[0] for r in (d.get("PacketFilter") or []) for x in (r.get("Srcs") or []) if "." in x}); print("\n".join("  "+i for i in s) if s else "  (none)")'

ts-net: ## Routes and DNS the tunnel installs (breaks Universal Clipboard)
	@echo "routes via utun:"
	@netstat -rn -f inet | awk '$$NF ~ /utun/ {print "  "$$0}'
	@echo "DNS resolvers:"
	@scutil --dns | grep 'nameserver\[0\]' | sort -u | sed 's/^/  /'

ts-web: ## Serve the browser UI on :5252 (replaces the menu bar app)
	sudo $(TS) set --webclient
	@echo "browse to http://`$(TS) ip -4`:5252"

ts-web-off: ## Stop serving the browser UI
	sudo $(TS) set --webclient=false

ts-daemon: ## Re-register the daemon (needed after `brew upgrade tailscale`)
	sudo tailscaled install-system-daemon
	@echo "note: the daemon runs /usr/local/bin/tailscaled, a copy separate from Homebrew's"

## ---- health -------------------------------------------------------------

health: ## One-shot headless readiness check
	@printf "  tailscale  : "; $(TS) status >/dev/null 2>&1 && echo up || echo DOWN
	@printf "  daemon     : "; test -f /Library/LaunchDaemons/com.tailscale.tailscaled.plist && echo "LaunchDaemon (pre-login)" || echo "NOT a system daemon"
	@printf "  ssh 22     : "; netstat -an | grep -q '\.22 .*LISTEN' && echo listening || echo DOWN
	@printf "  vnc 5900   : "; netstat -an | grep -q '\.5900.*LISTEN' && echo listening || echo DOWN
	@printf "  sleep      : "; pmset -g custom | awk '/ sleep /{print $$2; exit}'
	@printf "  filevault  : "; fdesetup status | head -1

fv: ## FileVault status
	@fdesetup status
	@printf "  authrestart supported: "; fdesetup supportsauthrestart

fv-on: ## Enable FileVault — PRINTS A RECOVERY KEY, store it off this machine
	sudo fdesetup enable

fv-off: ## Disable FileVault (decrypts in the background; stays usable)
	sudo fdesetup disable

fv-restart: ## Reboot and come back UNLOCKED — the only safe remote reboot with FileVault on
	@printf "authenticated restart of `hostname -s` now? [y/N] " && read a && [ "$$a" = y ] || exit 1
	sudo fdesetup authrestart

fv-arm: ## Stash the key so the NEXT restart self-unlocks. Does NOT restart now.
	@echo "The FDE unlock key is copied into memory and the SMC and stays there"
	@echo "until some restart consumes it. Arm shortly before you need it."
	sudo fdesetup authrestart -delayminutes -1

fv-restart-in: ## Delayed authenticated restart, MINS from now (MINS=10)
	@test -n "$(MINS)" || { echo "usage: make fv-restart-in MINS=10"; exit 1; }
	@echo "this WILL reboot in $(MINS) minutes"
	sudo fdesetup authrestart -delayminutes $(MINS)

power-headless: ## Never sleep or lock; auto-restart after power loss
	sudo pmset -a sleep 0 displaysleep 0 disksleep 0 autorestart 1 womp 1
	defaults -currentHost write com.apple.screensaver idleTime -int 0
	@echo "screen lock must be cleared separately (prompts for your password):"
	@echo "  sysadminctl -screenLock off -password"

power-status: ## Show the settings that matter when running headless
	@pmset -g custom | grep -E ' (sleep|displaysleep|disksleep|womp|autorestart|tcpkeepalive) ' | sed 's/^/  /'
	@printf "  screensaver idle : "; defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null || echo "(unset)"
	@printf "  screen lock      : "; sysadminctl -screenLock status 2>&1 | tail -1 | sed 's/.*sysadminctl[^ ]* //'

## ---- remote access ------------------------------------------------------

terminfo: ## Push ghostty terminfo to a host so backspace works: HOST=user@host
	@test -n "$(HOST)" || { echo "usage: make terminfo HOST=user@host"; exit 1; }
	infocmp -x xterm-ghostty | ssh $(HOST) -- tic -x -o '~/.terminfo' -

mosh: ## Connect over mosh (survives sleep and roaming): HOST=user@host
	@test -n "$(HOST)" || { echo "usage: make mosh HOST=user@host"; exit 1; }
	mosh $(HOST)

## ---- dotfiles -----------------------------------------------------------

brew-sync: ## Install everything in the Brewfile
	brew bundle --file=homebrew/Brewfile
