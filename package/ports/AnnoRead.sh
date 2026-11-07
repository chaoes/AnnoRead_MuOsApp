#!/bin/bash
# AnnoRead: native SDL gamepad input + the application's own virtual keyboard.

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
for candidate in /opt/system/Tools/PortMaster /opt/tools/PortMaster \
    "$XDG_DATA_HOME/PortMaster" /PortMaster /mmc/MUOS/PortMaster \
    /mnt/mmc/MUOS/PortMaster /roms/ports/PortMaster; do
    if [ -f "$candidate/control.txt" ]; then
        controlfolder="$candidate"
        break
    fi
done
if [ -z "${controlfolder:-}" ]; then
    echo "AnnoRead: PortMaster/control.txt not found. Install/update PortMaster."
    exit 1
fi
source "$controlfolder/control.txt"
[ -f "$controlfolder/mod_${CFW_NAME}.txt" ] && source "$controlfolder/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/${directory#/}/ports/annoread"
cd "$GAMEDIR" || exit 1
exec > >(tee "$GAMEDIR/log.txt") 2>&1
echo "AnnoRead PortMaster launcher (AArch64, GLIBC >= 2.38, LÖVE 11.5)"

# Always restore muOS idle settings and PortMaster's platform state on exit.
power_dir=/run/muos/global/settings/power
power_names=()
power_values=()
cleanup() {
    trap - EXIT HUP INT TERM
    local i
    for i in "${!power_names[@]}"; do
        printf '%s\n' "${power_values[$i]}" > "$power_dir/${power_names[$i]}"
    done
    pm_finish
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() { echo "AnnoRead: $*"; exit 1; }
[ "${DEVICE_ARCH:-}" = aarch64 ] || fail "This package requires AArch64 (got ${DEVICE_ARCH:-unknown})."
if command -v getconf >/dev/null 2>&1; then
    glibc_version=$(getconf GNU_LIBC_VERSION 2>/dev/null)
    glibc_version=${glibc_version#glibc }
    if [[ "$glibc_version" =~ ^([0-9]+)\.([0-9]+) ]]; then
        (( BASH_REMATCH[1] > 2 || (BASH_REMATCH[1] == 2 && BASH_REMATCH[2] >= 38) )) \
            || fail "GLIBC >= 2.38 required; found $glibc_version."
    fi
fi
command -v curl >/dev/null 2>&1 || fail "curl is required for book sources and TTS."
curl_version=$(curl --version | head -n 1)
if [[ "$curl_version" =~ ^curl\ ([0-9]+)\.([0-9]+) ]]; then
    (( BASH_REMATCH[1] > 7 || (BASH_REMATCH[1] == 7 && BASH_REMATCH[2] >= 75) )) \
        || fail "curl >= 7.75 required; found $curl_version."
fi
runtime="$controlfolder/runtimes/love_11.5/love.txt"
[ -f "$runtime" ] || fail "Install the love_11.5 runtime in PortMaster first."
source "$runtime"
[ -x "$LOVE_BINARY" ] || fail "LÖVE executable missing: $LOVE_BINARY"

CONFDIR="$GAMEDIR/conf"
mkdir -p "$CONFDIR" || exit 1
export XDG_DATA_HOME="$CONFDIR"
export XDG_CONFIG_HOME="$CONFDIR"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# Preserve the existing muOS reading/listening behaviour only when its writable
# power settings exist. Other firmware power management is outside this port.
for name in idle_display idle_sleep; do
    if [ -r "$power_dir/$name" ] && [ -w "$power_dir/$name" ]; then
        power_names+=("$name")
        power_values+=("$(cat "$power_dir/$name")")
        printf '%s\n' 86400 > "$power_dir/$name"
    fi
done

# Use the app's native gamepad support. No -c mapping and no external keyboard;
# gptokeyb supplies PortMaster's emergency exit only.
$GPTOKEYB "$LOVE_GPTK" &
pm_platform_helper "$LOVE_BINARY"
# Same environment as LOVE_RUN, with quoted paths. Keep the application root as
# cwd for the FFI library and user-imported sources. No ICMP-only online gate.
env LD_LIBRARY_PATH="$RUNTIME_DIR/libs.$DEVICE_ARCH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$LOVE_BINARY" "$GAMEDIR"
exit $?
