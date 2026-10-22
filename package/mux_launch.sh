#!/bin/sh
# HELP: 阿诺阅读 - 多书源小说阅读器
# ICON: read
# GRID: 阿诺阅读

. /opt/muos/script/var/func.sh

# The reader shells out to `curl` for all HTTP, so ensure the system bin dirs are
# on PATH even if this script is launched from a minimal environment.
export PATH="/usr/bin:/usr/sbin:/bin:/sbin:$PATH"

APP_BIN="love"
SETUP_APP "$APP_BIN" ""

# -----------------------------------------------------------------------------
# muOS Ports / Application 通用防闲置省电管理
# 听书 / 长时间阅读时避免触发 muOS 系统的自动降亮度与自动休眠导致无声
POWER_DIR="/run/muos/global/settings/power"
DISPLAY_FILE="$POWER_DIR/idle_display"
SLEEP_FILE="$POWER_DIR/idle_sleep"

# 临时延长闲置超时至 24 小时（86400 秒）
TIMEOUT=86400

OLD_DISPLAY=""
OLD_SLEEP=""
HAS_DISPLAY=0
HAS_SLEEP=0

if [ -r "$DISPLAY_FILE" ] && [ -w "$DISPLAY_FILE" ]; then
	OLD_DISPLAY="$(cat "$DISPLAY_FILE")"
	HAS_DISPLAY=1
fi

if [ -r "$SLEEP_FILE" ] && [ -w "$SLEEP_FILE" ]; then
	OLD_SLEEP="$(cat "$SLEEP_FILE")"
	HAS_SLEEP=1
fi

restore_power() {
	trap - EXIT HUP INT TERM

	if [ "$HAS_DISPLAY" -eq 1 ]; then
		printf '%s\n' "$OLD_DISPLAY" > "$DISPLAY_FILE"
	fi

	if [ "$HAS_SLEEP" -eq 1 ]; then
		printf '%s\n' "$OLD_SLEEP" > "$SLEEP_FILE"
	fi
}

trap 'restore_power' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$HAS_DISPLAY" -eq 1 ]; then
	printf '%s\n' "$TIMEOUT" > "$DISPLAY_FILE"
fi

if [ "$HAS_SLEEP" -eq 1 ]; then
	printf '%s\n' "$TIMEOUT" > "$SLEEP_FILE"
fi

# -----------------------------------------------------------------------------
# Resolve the application directory (muOS passes it as $1; fall back to $0).
LOVEDIR="$1"
[ -n "$LOVEDIR" ] || LOVEDIR="$(cd "$(dirname "$0")" && pwd)"
cd "$LOVEDIR" || exit

# Hijack the library search path so our bundled LÖVE runtime + LuaJIT win over
# anything the system might provide (muOS ships no system `love`).
export LD_LIBRARY_PATH="$LOVEDIR/libs:$LD_LIBRARY_PATH"

# Persistent user data (book sources, bookshelf, chapter cache, reader settings).
# LÖVE honours XDG_DATA_HOME, so these land in <app>/conf and survive both
# reboots and reinstalling the .muxapp (the archive never ships a conf/ folder).
CONFDIR="$LOVEDIR/conf"
mkdir -p "$CONFDIR"
export XDG_DATA_HOME="$CONFDIR"
export XDG_CONFIG_HOME="$CONFDIR"

# -----------------------------------------------------------------------------
# Network pre-check. On a disconnected handheld, a getaddrinfo() call inside the
# game can block the whole process for ~30s (frozen UI, unresponsive hotkeys).
# Probe once here and hand the result to the game so it can degrade to offline
# mode instead of dead-locking.
export GAME_NETWORK_AVAILABLE=0
if ping -c 1 -W 1 223.5.5.5 >/dev/null 2>&1 || ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
	export GAME_NETWORK_AVAILABLE=1
fi

# Repair the exec bit that Windows-built archives may lose.
[ -f "$LOVEDIR/love" ] && chmod +x "$LOVEDIR/love" 2>/dev/null

# -----------------------------------------------------------------------------
# Launch: prefer the bundled runtime, degrade to a system love only if present.
# Note: Keep in FOREGROUND so traps fire on exit and restore original power settings.
if [ -x "$LOVEDIR/love" ]; then
	"$LOVEDIR/love" "$LOVEDIR" > "$LOVEDIR/log.txt" 2>&1
else
	love "$LOVEDIR" > "$LOVEDIR/log.txt" 2>&1
fi
