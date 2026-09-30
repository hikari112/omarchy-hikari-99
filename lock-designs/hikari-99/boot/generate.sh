#!/bin/bash
# Boot screen twin of the Hikari 99 lock design. Stages a Plymouth theme into
# the directory given as $1; the lock explorer's plymouth/apply.sh ships it.
# Colors and the wallpaper come from the active Omarchy theme, so re-apply
# after a theme switch (the explorer offers to). The drawing is done by
# render.py next to this file; see it for what the screen does.
set -euo pipefail
here="$(dirname "$(realpath "$0")")"
plugin="${LOCK_EXPLORER_DIR:-$HOME/.config/omarchy/plugins/io.github.sirjul1337.lock-explorer}"
source "$plugin/plymouth/common.sh"

staging="${1:?usage: generate.sh <staging-dir>}"
mkdir -p "$staging"

# The drawing needs Pillow; the system Python has it with python-pillow
py=""
for candidate in python3 /usr/bin/python3; do
  if "$candidate" -c 'import PIL' 2>/dev/null; then py=$candidate; break; fi
done
[[ -n $py ]] || { echo "Pillow is not installed: omarchy pkg add python-pillow" >&2; exit 1; }

night=$(theme_color darker_background background)
accent=$(theme_color accent foreground)
lilac=$(theme_color bright_magenta accent)
light=$(theme_color bright_foreground foreground)
ink=$(theme_color light_foreground foreground)
error=$(theme_color red accent)
colors=$(printf '{"night":"#%s","accent":"#%s","lilac":"#%s","light":"#%s","ink":"#%s","error":"#%s"}' \
  "$night" "$accent" "$lilac" "$light" "$ink" "$error")

# Without the real fonts fc-match hands back one without Japanese
for family in 'Klee One' 'Murecho'; do
  [[ $(fc-match -f '%{family}' "$family") == *"$family"* ]] || { echo "Font $family is not installed" >&2; exit 1; }
done
klee=$(fc-match -f '%{file}' 'Klee One')
murecho=$(fc-match -f '%{file}' 'Murecho')
fonts=$("$py" -c 'import json,sys; print(json.dumps({"klee": sys.argv[1], "murecho": sys.argv[2]}))' "$klee" "$murecho")

wallpaper=$(readlink -f "$HOME/.local/state/omarchy/current/background")
[[ -f $wallpaper ]] || { echo "No wallpaper at ~/.local/state/omarchy/current/background" >&2; exit 1; }

# One drawing set per monitor size, so every screen gets the scene drawn for
# it; a screen with no set of its own scales the nearest. Plymouth shows each
# screen unrotated, in the mode the kernel picks (normally the one Hyprland
# uses too), so it is the mode's size that counts.
# HIKARI_BOOT_SIZES="2560x1440,1920x1080" picks them by hand.
sizes="${HIKARI_BOOT_SIZES:-}"
if [[ -z $sizes && -n ${PREVIEW_ONLY:-} ]]; then
  sizes=1920x1080   # the explorer's thumbnail only needs one
fi
if [[ -z $sizes ]] && command -v hyprctl >/dev/null 2>&1; then
  sizes=$(hyprctl monitors all -j 2>/dev/null |
    jq -r '[.[] | select(.width > 0 and .height > 0) | "\(.width)x\(.height)"] | unique | join(",")' 2>/dev/null || true)
fi
[[ $sizes =~ ^[0-9]+x[0-9]+(,[0-9]+x[0-9]+)*$ ]] || sizes=1920x1080,3840x2160
"$py" -B "$here/render.py" "$staging" "$wallpaper" "$colors" "$fonts" "$sizes" >/dev/null
rm -f "$staging/layout.json" "$staging/preview-full.png"

write_theme_ini "$staging" "$night" "$(mono_font_family)"
echo hikari-99 > "$staging/design"
