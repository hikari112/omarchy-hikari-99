#!/bin/bash
# Hikari 99 lock screens for Omarchy: Hikari 99, Hikari 99 Real Sky,
# Tsukiyo 99 and Tsukiyo 99 Real Sky, for the Lock Screen Explorer plugin.
# Optional: the
# Sky 99 theme or its wallpaper, the Living Sky desktop (experimental), the
# matching boot screen, a lock screen that stays lit, and Keychron Q6 Max
# keyboard lighting.
#
#   ./install.sh                 ask about each part
#   ./install.sh --all           everything, without asking (Sky 99 theme)
#   ./install.sh --yes           the lock screens (and their fonts) only
#   ./install.sh --yes --theme --boot --night 45 --set my-hikari-99
#   ./install.sh --uninstall     take everything this installed out again
#
# Options:
#   --theme            install the Sky 99 theme (and apply it)
#   --wallpaper        add the wallpaper to your current theme's backgrounds
#   --living-desktop   install the Living Sky desktop plugin (experimental)
#   --boot             make the boot screen (disk unlock) match Hikari 99
#   --night <minutes>  how long a lock takes to reach night, 2 to 1440
#                      (Hikari 99 and Tsukiyo 99; made for 22)
#   --stay-lit         keep the lock screen lit until night has come (up to
#                      60 minutes; the explorer blanks it after 5 seconds)
#   --keyboard         Keychron Q6 Max lighting (ANSI with knob, on its cable)
#   --set <id>         make one of the four your lock screen:
#                      my-hikari-99, my-hikari-99-real-sky, my-tsukiyo-99, my-tsukiyo-99-real-sky
#   --all              --theme --living-desktop --boot --stay-lit, and
#                      --keyboard when a Q6 Max is plugged in; implies --yes
#   --no-fonts         don't install the bundled fonts (Klee One, Murecho)
#   --yes              don't ask; do only what the options say
#   --uninstall        remove what this installed (fonts and themes you chose to keep stay)
set -euo pipefail

here="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
# Omarchy's own scripts use these paths as they are, so this does too
config="$HOME/.config/omarchy"
designs="$config/lock-designs"
plugins="$config/plugins"
explorer_id="io.github.sirjul1337.lock-explorer"
explorer_url="https://github.com/SirJul1337/omarchy-lock-explorer.git"
explorer_boot="$plugins/$explorer_id/plymouth"
boot_state="$HOME/.local/state/omarchy/lock-explorer-boot"
sky_id="io.github.hikari112.living-sky"
record="$designs/shared/.omarchy-hikari-99"
settings="$designs/shared/.omarchy-hikari-99-settings"
fonts_dir="$HOME/.local/share/fonts/omarchy-hikari-99"
data_dir="$HOME/.local/share/omarchy-hikari-99"
unit_dir="$HOME/.config/systemd/user"
glow_unit="keychron-glow.service"
udev_rule="/etc/udev/rules.d/70-keychron-hidraw.rules"
night_file="$designs/shared/night-minutes"
ids=(my-hikari-99 my-hikari-99-real-sky my-tsukiyo-99 my-tsukiyo-99-real-sky)
# Tsukiyo was called that until 1.0.0; now Tsukiyo 99
old_ids=(my-tsukiyo my-tsukiyorealsky)

want_theme="" want_wallpaper="" want_sky="" want_boot="" want_lit="" want_keyboard=""
set_design="" night="" no_fonts="" yes="" uninstall="" all=""
while (($#)); do
  case "$1" in
    --theme) want_theme=1 ;;
    --wallpaper) want_wallpaper=1 ;;
    --living-desktop) want_sky=1 ;;
    --boot) want_boot=1 ;;
    --stay-lit) want_lit=1 ;;
    --keyboard) want_keyboard=1 ;;
    --set) set_design="${2:-}"; shift ;;
    --night)
      night="${2:-}"; shift
      if ! [[ $night =~ ^[0-9]+$ ]] || ((10#$night < 2 || 10#$night > 1440)); then
        echo "--night takes whole minutes, 2 to 1440" >&2
        exit 1
      fi
      night=$((10#$night))
      ;;
    --all) all=1 yes=1 want_theme=1 want_sky=1 want_boot=1 want_lit=1 ;;
    --no-fonts) no_fonts=1 ;;
    --yes | -y) yes=1 ;;
    --uninstall) uninstall=1 ;;
    -h | --help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
  shift
done

say() { printf '\033[1m%s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }
warn() { printf '\033[33m  %s\033[0m\n' "$*" >&2; }

# Ask a yes/no question; with --yes the answer is the option given (or no)
ask() {
  local question="$1" preset="${2:-}"
  if [[ -n $yes ]]; then [[ -n $preset ]]; return; fi
  if [[ -n $preset ]]; then return 0; fi
  if command -v gum >/dev/null 2>&1; then gum confirm "$question"; else
    local reply; read -r -p "$question [y/N] " reply; [[ $reply == [yY]* ]]
  fi
}

shell_ipc() { omarchy-shell -q "$@" >/dev/null 2>&1 || true; }

# Record every file put in place, so --uninstall can take exactly those out
remember() { mkdir -p "$(dirname "$record")"; printf '%s\n' "$1" >>"$record"; }
recorded() { [[ -f $record ]] && grep -qxF "$1" "$record"; }

# Copy a file into place; an existing different file is kept as .bak-<time>
place() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -e $dst ]] && ! cmp -s "$src" "$dst"; then
    mv "$dst" "$dst.bak-$(date +%s)"
    note "kept your previous $(basename "$dst") as $(basename "$dst").bak-*"
  fi
  cp "$src" "$dst"
  remember "$dst"
}

# The Q6 Max (ANSI, knob) raw HID node, when it is plugged in
keychron_node() {
  local n
  for n in /sys/class/hidraw/hidraw*; do
    grep -q "HID_ID=0003:00003434:00000860" "$n/device/uevent" 2>/dev/null || continue
    [[ $(head -c 3 "$n/device/report_descriptor" 2>/dev/null | od -An -tx1 | tr -d ' \n') == 0660ff ]] || continue
    echo "/dev/${n##*/}"
    return 0
  done
  return 1
}

# A rule already giving the user the Keychron raw HID interface?
keychron_rule_present() {
  grep -lqs 'idVendor}=="3434"' /etc/udev/rules.d/*.rules /usr/lib/udev/rules.d/*.rules
}

# The lock screen's blank delay, in ms, as the explorer reports it
blank_delay() { omarchy-shell lock status 2>/dev/null | jq -r '.blankMs // empty' 2>/dev/null || true; }

uninstall_all() {
  say "Removing the Hikari 99 lock screens"
  local current
  current=$(omarchy-shell lock design 2>/dev/null || true)
  for id in "${ids[@]}" "${old_ids[@]}"; do
    if [[ $current == "$id" ]]; then
      shell_ipc lock setDesign card
      note "lock screen set back to Greeting Card (the explorer's default)"
    fi
  done

  # The boot screen goes back to Omarchy's before its generator goes
  if [[ $(cut -d' ' -f1 "$boot_state" 2>/dev/null) == hikari-99 && -f $explorer_boot/apply.sh ]]; then
    note "putting Omarchy's own boot screen back (asks for your password)"
    if ! bash "$explorer_boot/apply.sh" stock; then
      warn "the boot screen was not restored; do it later with: bash $explorer_boot/apply.sh stock"
    fi
  fi

  if recorded "$unit_dir/$glow_unit"; then
    systemctl --user disable --now "$glow_unit" >/dev/null 2>&1 || true
    note "keyboard lighting stopped (the board keeps its last colors until you pick another effect)"
  fi

  if [[ -f $settings ]]; then
    local before
    before=$(sed -n 's/^blank_ms_before=//p' "$settings")
    if [[ $before =~ ^[0-9]+$ ]]; then
      shell_ipc lock setBlankDelay "$before"
      note "lock screen blanks after $((before / 1000)) s again, as before"
    fi
    rm -f -- "$settings"
  fi

  local background
  background=$(readlink -f "$HOME/.local/state/omarchy/current/background" 2>/dev/null || true)
  if [[ -f $record ]]; then
    while IFS= read -r f; do
      [[ -n $f ]] && [[ -e $f || -L $f ]] || continue
      case "$f" in
        "$config"/themes/*) ;;       # themes are asked about below
        "$plugins"/"$sky_id") ;;     # the plugin is handled below
        "$fonts_dir"/*) ;;           # fonts stay: other apps may use them now
        /etc/*) ;;                   # the udev rule is asked about below
        *)
          if [[ $(readlink -f "$f") == "$background" ]]; then
            warn "kept $f: it is your current background (pick another, then delete it)"
          else
            rm -f -- "$f"
          fi
          ;;
      esac
    done <"$record"
  fi
  rmdir "$designs/hikari-99/boot" "$designs/hikari-99" "$designs/tsukiyo-99" "$designs/tsukiyo" "$data_dir" 2>/dev/null || true
  systemctl --user daemon-reload >/dev/null 2>&1 || true

  if [[ -d $plugins/$sky_id ]]; then
    omarchy plugin disable "$sky_id" >/dev/null 2>&1 || true
    rm -rf -- "${plugins:?}/$sky_id"
    note "removed the Living Sky desktop (Omarchy's own background is back)"
  fi
  if recorded "$config/themes/sky-99"; then
    if ask "Remove the Sky 99 theme too?"; then
      if [[ $(omarchy theme current 2>/dev/null) == "sky-99" ]]; then
        warn "Sky 99 is your current theme: switch themes first, then remove it with: omarchy theme remove sky-99"
      else
        rm -rf -- "${config:?}/themes/sky-99"
        note "removed the Sky 99 theme"
      fi
    fi
  fi
  if recorded "$udev_rule" && [[ -f $udev_rule ]]; then
    if ask "Remove the udev rule that lets you reach Keychron keyboards (Keychron Launcher and VIA use it too)?"; then
      if pkexec rm -f "$udev_rule"; then note "removed $udev_rule"; else warn "kept $udev_rule"; fi
    else
      note "kept $udev_rule"
    fi
  fi
  rm -f -- "$record" "$designs/shared/lock-state.js"
  rmdir "$designs/shared" 2>/dev/null || true
  shell_ipc lock rescanDesigns
  note "fonts stay in $fonts_dir (delete the folder if you don't want them)"
  say "Done."
}

need_font() { ! fc-list : family 2>/dev/null | grep -qi "^$1\(,\|$\)"; }

# The bundled fonts (SIL OFL, with their licenses), for whichever is missing
install_fonts() {
  local got=""
  if need_font "Klee One"; then
    place "$here/fonts/KleeOne-Regular.ttf" "$fonts_dir/KleeOne-Regular.ttf"
    place "$here/fonts/KleeOne-SemiBold.ttf" "$fonts_dir/KleeOne-SemiBold.ttf"
    place "$here/fonts/OFL-KleeOne.txt" "$fonts_dir/OFL-KleeOne.txt"
    got=1
  fi
  if need_font "Murecho"; then
    place "$here/fonts/Murecho[wght].ttf" "$fonts_dir/Murecho[wght].ttf"
    place "$here/fonts/OFL-Murecho.txt" "$fonts_dir/OFL-Murecho.txt"
    got=1
  fi
  if [[ -n $got ]]; then
    fc-cache -f "$fonts_dir" >/dev/null 2>&1 || true
    note "fonts installed in $fonts_dir"
  else
    note "Klee One and Murecho are already installed"
  fi
}

# Another enabled plugin already standing in for omarchy.background?
other_background_clone() {
  local m id
  for m in "$plugins"/*/manifest.json; do
    [[ -f $m ]] || continue
    id=$(jq -r '.id // empty' "$m" 2>/dev/null)
    [[ -n $id && $id != "$sky_id" ]] || continue
    if [[ $(jq -r '.omarchy.clonedFrom // empty' "$m" 2>/dev/null) == "omarchy.background" ]] &&
      jq -e --arg id "$id" '(.plugins // []) | any(.id == $id)' "$config/shell.json" >/dev/null 2>&1; then
      echo "$id"
      return
    fi
  done
}

# Pillow, for drawing the boot screen
have_pillow() {
  local py
  for py in python3 /usr/bin/python3; do "$py" -c 'import PIL' 2>/dev/null && return 0; done
  return 1
}

install_boot() {
  if [[ ! -f $explorer_boot/apply.sh ]]; then
    warn "The boot screen goes in through the Lock Screen Explorer, which is not installed. Skipped."
    return
  fi
  if ! have_pillow; then
    note "drawing the boot screen needs Pillow (python-pillow)"
    if ask "Install python-pillow (omarchy pkg add python-pillow)?" "$want_boot"; then
      omarchy pkg add python-pillow || true
    fi
    have_pillow || { warn "Pillow is missing, so the boot screen was skipped (./install.sh --boot to try again)"; return; }
  fi
  for f in generate.sh render.py script_multi.py strokes.json; do
    place "$here/lock-designs/hikari-99/boot/$f" "$designs/hikari-99/boot/$f"
  done
  chmod +x "$designs/hikari-99/boot/generate.sh"
  # The explorer finds boot screens by folder under its plymouth/; this one
  # lives with the design and is linked in
  local link="$explorer_boot/hikari-99"
  if [[ -e $link || -L $link ]] && [[ $(readlink -f "$link") != "$(readlink -f "$designs/hikari-99/boot")" ]]; then
    mv "$link" "$link.bak-$(date +%s)"
    note "kept the explorer's previous hikari-99 boot folder as hikari-99.bak-*"
  fi
  ln -sfn "$designs/hikari-99/boot" "$link"
  remember "$link"
  note "drawing the boot screen for your monitors and theme (about a minute), then it asks for your password"
  if bash "$explorer_boot/apply.sh" hikari-99; then
    note "boot screen set: you'll see it at the disk unlock on the next boot"
    note "it follows theme changes on its own (the explorer redraws it)"
  else
    warn "the boot screen was not applied; try again with: bash $explorer_boot/apply.sh hikari-99"
  fi
}

# Minutes from locking to night: the setting, or 22 as made
night_minutes() {
  local n
  n=$(head -n 1 "$night_file" 2>/dev/null | grep -oE '^[0-9]+' || true)
  echo "${n:-22}"
}

# Long enough to see night come, and the explorer's limit of an hour
lit_minutes() {
  local m=$(($(night_minutes) + 8))
  ((m > 60)) && m=60
  echo "$m"
}

set_night() {
  local n="$1"
  if [[ ! -f $night_file ]]; then
    ((n == 22)) && { note "night comes after 22 minutes (as made)"; return; }
    mkdir -p "$(dirname "$night_file")"
    printf '%s\n' "$n" >"$night_file"
    remember "$night_file"
  else
    printf '%s\n' "$n" >"$night_file"
  fi
  note "night comes after $n minutes: evening at about $(((n * 5 + 11) / 22)), the first stars at about $(((n * 13 + 11) / 22))"
}

choose_night() {
  local now="$1" pick
  if command -v gum >/dev/null 2>&1; then
    pick=$(gum choose --header "How long should a lock take to reach night? (Hikari 99 and Tsukiyo 99; the Real Sky versions follow the sun)" \
      "$now minutes (now)" 10 15 22 30 45 60 90 "other" || true)
    pick=${pick%% *}
    if [[ $pick == other ]]; then pick=$(gum input --placeholder "minutes, 2 to 1440" || true); fi
  else
    read -r -p "Minutes from locking to night, 2 to 1440 [$now]: " pick || true
  fi
  pick=${pick:-$now}
  if [[ $pick =~ ^[0-9]+$ ]] && ((10#$pick >= 2 && 10#$pick <= 1440)); then
    echo $((10#$pick))
  else
    warn "'$pick' is not 2 to 1440 minutes; keeping $now"
    echo "$now"
  fi
}

stay_lit() {
  local now lit_ms
  lit_ms=$(($(lit_minutes) * 60000))
  now=$(blank_delay)
  if [[ $now =~ ^[0-9]+$ ]] && ((now >= lit_ms)); then
    note "the lock screen already stays lit $((now / 60000)) minutes"
    return
  fi
  if [[ ! -f $settings && $now =~ ^[0-9]+$ ]]; then
    mkdir -p "$(dirname "$settings")"
    printf 'blank_ms_before=%s\n' "$now" >"$settings"
  fi
  if [[ $(omarchy-shell lock setBlankDelay "$lit_ms" 2>/dev/null) == ok ]]; then
    note "the lock screen now stays lit $((lit_ms / 60000)) minutes before the display sleeps"
    (($(night_minutes) + 8 > 60)) && note "(an hour at most: night comes on while the screen sleeps, and is there when you wake it)"
  else
    warn "could not set it; in the explorer's settings, set the screen blanking to $((lit_ms / 60000)) minutes"
  fi
}

install_keyboard() {
  place "$here/optional/keyboard/keychron-glow.py" "$data_dir/keychron-glow.py"
  chmod +x "$data_dir/keychron-glow.py"
  place "$here/optional/keyboard/$glow_unit" "$unit_dir/$glow_unit"
  local node
  node=$(keychron_node || true)
  if [[ -n $node && -r $node && -w $node ]] || { [[ -z $node ]] && keychron_rule_present; }; then
    : # the board is reachable already
  elif keychron_rule_present; then
    note "a udev rule for Keychron is there; unplug the keyboard and plug it back in"
  else
    note "the keyboard's lighting interface needs a udev rule (asks for your password)"
    # shellcheck disable=SC2016 # expanded by the root shell, from its arguments
    if pkexec sh -c 'install -m 0644 "$1" "$2" && udevadm control --reload && udevadm trigger --subsystem-match=hidraw --action=change' \
      sh "$here/optional/keyboard/70-keychron-hidraw.rules" "$udev_rule"; then
      remember "$udev_rule"
      note "installed $udev_rule"
    else
      warn "no udev rule: the lighting can't reach the keyboard until one is in place (see the README)"
    fi
  fi
  systemctl --user daemon-reload
  if systemctl --user enable --now "$glow_unit" >/dev/null 2>&1; then
    note "keyboard lighting on (it takes over the board's lighting; stop it with: systemctl --user disable --now $glow_unit)"
  else
    warn "could not start it: systemctl --user status $glow_unit"
  fi
  [[ -n $node ]] || note "no Q6 Max is plugged in right now; the lighting starts when it is (on its cable)"
}

if [[ -n $uninstall ]]; then
  uninstall_all
  exit 0
fi

command -v omarchy-shell >/dev/null 2>&1 || { echo "This is for Omarchy (omarchy-shell was not found)." >&2; exit 1; }

say "Hikari 99 lock screens"

# 1. The Lock Screen Explorer, which these designs are made for
if [[ ! -d $plugins/$explorer_id ]]; then
  warn "The Lock Screen Explorer plugin is not installed; these lock screens are designs for it."
  if ask "Install it now (omarchy plugin add $explorer_url --enable)?" "$all"; then
    omarchy plugin add "$explorer_url" --enable --yes
  else
    note "Install it later with: omarchy plugin add $explorer_url --enable"
  fi
else
  version=$(jq -r '.version // "?"' "$plugins/$explorer_id/manifest.json" 2>/dev/null || echo "?")
  note "Lock Screen Explorer $version found (made with 1.9.1)"
fi

# 2. The four designs, their shaders, and the memory their screens share
for f in Hikari-99.qml Hikari-99-Real-Sky.qml Tsukiyo-99.qml Tsukiyo-99-Real-Sky.qml \
  hikari-99/sky.frag hikari-99/build.sh tsukiyo-99/sky.frag tsukiyo-99/build.sh shared/lock-state.js; do
  place "$here/lock-designs/$f" "$designs/$f"
done
for f in "$here"/lock-designs/hikari-99/*.qsb "$here"/lock-designs/tsukiyo-99/*.qsb; do
  place "$f" "$designs/$(basename "$(dirname "$f")")/$(basename "$f")"
done
chmod +x "$designs/hikari-99/build.sh" "$designs/tsukiyo-99/build.sh"
note "lock screens installed in $designs"

# Tsukiyo before it became Tsukiyo 99: take out the old files this installed
renamed_from=""
for f in "$designs/Tsukiyo.qml" "$designs/TsukiyoRealSky.qml" "$designs/tsukiyo/sky.frag" \
  "$designs/tsukiyo/build.sh" "$designs"/tsukiyo/sky-*.frag.qsb; do
  if recorded "$f" && [[ -e $f ]]; then rm -f -- "$f"; renamed_from=1; fi
done
rmdir "$designs/tsukiyo" 2>/dev/null || true
if [[ -n $renamed_from ]]; then
  note "Tsukiyo is Tsukiyo 99 now (the name was taken): the old files are gone"
  case $(omarchy-shell lock design 2>/dev/null || true) in
    my-tsukiyo) [[ -n $set_design ]] || set_design=my-tsukiyo-99 ;;
    my-tsukiyorealsky) [[ -n $set_design ]] || set_design=my-tsukiyo-99-real-sky ;;
  esac
fi

# 3. Fonts
if [[ -z $no_fonts ]]; then install_fonts; fi

# 4. How long a lock takes to reach night
if [[ -z $night && -z $yes ]]; then night=$(choose_night "$(night_minutes)"); fi
if [[ -n $night ]]; then set_night "$night"; fi

shell_ipc lock rescanDesigns
shell_ipc lock reloadDesigns

# 5. The Sky 99 theme
if ask "Install the Sky 99 theme (and apply it)?" "$want_theme"; then
  src="$here/optional/theme/sky-99" dst="$config/themes/sky-99"
  if [[ -d $dst ]] && ! diff -rq "$src" "$dst" >/dev/null 2>&1; then
    mv "$dst" "$dst.bak-$(date +%s)"
    note "kept your previous sky-99 theme as sky-99.bak-*"
  fi
  mkdir -p "$dst"
  cp -r "$src/." "$dst/"
  remember "$dst"
  if omarchy theme set sky-99 >/dev/null 2>&1; then
    note "Sky 99 applied"
  else
    warn "installed; apply it with: omarchy theme set sky-99"
  fi
elif ask "Add the Sky 99 wallpaper to your current theme's backgrounds?" "$want_wallpaper"; then
  theme_name=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || echo default)
  wall="$config/backgrounds/$theme_name/hikari-99-sky.png"
  place "$here/optional/wallpaper/hikari-99-sky.png" "$wall"
  if omarchy theme bg set "$wall" >/dev/null 2>&1; then
    note "wallpaper set"
  else
    note "wallpaper added: $wall"
  fi
fi

# 6. The Living Sky desktop (experimental)
if ask "Install the Living Sky desktop (experimental: the wallpaper animated at your display's refresh; uses the GPU)?" "$want_sky"; then
  clone=$(other_background_clone || true)
  if [[ -n $clone ]]; then
    warn "'$clone' already replaces Omarchy's background; disable it first (omarchy plugin disable $clone). Skipped."
  else
    rm -rf -- "${plugins:?}/$sky_id"
    mkdir -p "$plugins"
    cp -r "$here/optional/living-desktop/$sky_id" "$plugins/$sky_id"
    remember "$plugins/$sky_id"
    omarchy plugin enable "$sky_id" >/dev/null
    note "Living Sky enabled. Run 'omarchy restart shell' once so its on/off command works:"
    note "  omarchy-shell background living false   (the plain wallpaper)"
    note "  omarchy-shell background living true"
  fi
fi

# 7. The boot screen, drawn from the theme and wallpaper now in place
if ask "Match the boot screen (the disk unlock when you start up; asks for your password)?" "$want_boot"; then
  install_boot
fi

# 8. Time for night to come
if ask "Keep the lock screen lit for $(lit_minutes) minutes, so evening and night come? (the explorer blanks it after 5 seconds)" "$want_lit"; then
  stay_lit
fi

# 9. Keyboard lighting, only for the board it is made for
if [[ -n $all && -z $want_keyboard ]] && keychron_node >/dev/null; then want_keyboard=1; fi
if [[ -n $want_keyboard ]] || { [[ -z $yes ]] && keychron_node >/dev/null; }; then
  if ask "Light your Keychron Q6 Max in the same sky, joining in when you lock?" "$want_keyboard"; then
    install_keyboard
  fi
fi

# 10. Which one to use
if [[ -z $set_design && -z $yes ]] && command -v gum >/dev/null 2>&1; then
  set_design=$(gum choose --header "Make one your lock screen?" \
    "my-hikari-99" "my-hikari-99-real-sky" "my-tsukiyo-99" "my-tsukiyo-99-real-sky" "not now" || true)
  [[ $set_design == "not now" ]] && set_design=""
fi
if [[ -z $set_design && -n $all ]]; then set_design=my-hikari-99; fi
if [[ -n $set_design ]]; then
  if [[ " ${ids[*]} " == *" $set_design "* ]]; then
    shell_ipc lock setDesign "$set_design"
    note "lock screen set to $set_design"
  else
    warn "unknown design '$set_design' (use one of: ${ids[*]})"
  fi
fi

say "Done."
note "Browse them with: omarchy-shell lock explore  (under Animation, or search 'hikari' / 'tsukiyo')"
note "Real Sky follows the sun where your timezone's city is. For your exact spot, put"
note "\"latitude longitude\" in degrees on one line in $designs/shared/location"
note "If a design shows the plain fallback, restart the shell once: omarchy restart shell"
