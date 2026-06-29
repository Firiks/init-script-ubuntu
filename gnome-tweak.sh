#!/bin/bash

# ─── GNOME Tweaks ────────────────────────────────────────────────────────────
# Run this as your NORMAL user (not root/sudo): gsettings writes to your
# per-user dconf via the session D-Bus. Under sudo it no-ops or lands in
# root's profile.
if [[ $EUID -eq 0 ]]; then
  echo "Do NOT run this with sudo/root — run it as your normal desktop user."
  exit 1
fi

echo "Applying GNOME tweaks"

# Appearance — dark mode system-wide
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'

# Titlebar — GNOME hides minimize/maximize by default, restore them
gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'

# Dock — minimize on click (was already set, keeping it here with other tweaks)
gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'minimize'

# Clock — show date and weekday, skip seconds (redraws every second, minor perf hit)
gsettings set org.gnome.desktop.interface clock-show-date true
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.interface clock-show-seconds false

# Battery — show percentage in top bar
gsettings set org.gnome.desktop.interface show-battery-percentage true

# Hot corners — disable (triggers accidentally while coding)
gsettings set org.gnome.desktop.interface enable-hot-corners false

# Touchpad — tap to click, natural scroll, two-finger scroll
gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true
gsettings set org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled true

# Night light — reduces blue light in the evening
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 4000

# Files (Nautilus)
gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view'
gsettings set org.gnome.nautilus.preferences sort-directories-first true
gsettings set org.gnome.nautilus.preferences show-create-link true
gsettings set org.gnome.nautilus.preferences show-hidden-files true
gsettings set org.gnome.nautilus.preferences show-image-thumbnails 'always'
gsettings set org.gnome.nautilus.preferences recursive-search 'always'
gsettings set org.gnome.nautilus.preferences show-delete-permanently true
gsettings set org.gnome.nautilus.preferences show-directory-item-counts 'always'

# Location services — disable (privacy)
gsettings set org.gnome.system.location enabled false

# Technical reporting — disable (privacy)
gsettings set org.gnome.desktop.privacy report-technical-problems false
gsettings set org.gnome.desktop.privacy send-software-usage-stats false

# Text scaling — leave at 1.0, adjust manually if needed
# gsettings set org.gnome.desktop.interface text-scaling-factor 1.1

# ─── GNOME Extensions ─────────────────────────────────────────────────────────
# Two groups:
#  1) BUILTIN  — shipped by the 'gnome-shell-extensions' apt package (installed by
#                post-install.sh). Just need enabling.
#  2) EGO      — fetched from extensions.gnome.org via `gext` (gnome-extensions-cli).
#                Each entry may list fallback UUIDs; if none install for the running
#                GNOME version, it's skipped (never aborts the script).
# NOTE: newly installed extensions only load after a session log-out/in (Wayland).
echo "Setting up GNOME extensions"

# Make user-installed tools (uv, gext) reachable
export PATH="$HOME/.local/bin:$PATH"

# --- Group 1: enable built-ins (UUID -> human name in comment) ---
BUILTIN_EXTENSIONS=(
  "auto-move-windows@gnome-shell-extensions.gcampax.github.com"        # Auto Move Windows
  "launch-new-instance@gnome-shell-extensions.gcampax.github.com"      # Launch new instance
  "native-window-placement@gnome-shell-extensions.gcampax.github.com"  # Native Window Placement
  "drive-menu@gnome-shell-extensions.gcampax.github.com"               # Removable Drive Menu
  "user-theme@gnome-shell-extensions.gcampax.github.com"               # User Themes
  "windowsNavigator@gnome-shell-extensions.gcampax.github.com"         # Window Navigator
  "workspace-indicator@gnome-shell-extensions.gcampax.github.com"      # Workspace Indicator
)
for uuid in "${BUILTIN_EXTENSIONS[@]}"; do
  if gnome-extensions list 2>/dev/null | grep -qx "$uuid"; then
    gnome-extensions enable "$uuid" 2>/dev/null && echo "  enabled: $uuid" \
      || echo "  ! could not enable: $uuid"
  else
    echo "  ! not installed (skip): $uuid"
  fi
done

# --- Bootstrap gext (gnome-extensions-cli) for EGO installs ---
GEXT=""
if command -v gext >/dev/null 2>&1; then
  GEXT="gext"
elif command -v uv >/dev/null 2>&1; then
  echo "  installing gnome-extensions-cli via uv..."
  uv tool install gnome-extensions-cli >/dev/null 2>&1 && GEXT="gext"
elif command -v pipx >/dev/null 2>&1; then
  pipx install gnome-extensions-cli >/dev/null 2>&1 && GEXT="gext"
fi
command -v "$GEXT" >/dev/null 2>&1 || GEXT=""   # verify it actually resolved

# install_ego "Label" uuid [fallback_uuid ...]
#   - if any candidate is already installed -> just enable it
#   - else install the first candidate that works for this GNOME version
#   - else skip (no abort)
install_ego() {
  local label="$1"; shift
  local uuid
  for uuid in "$@"; do
    if gnome-extensions list 2>/dev/null | grep -qx "$uuid"; then
      gnome-extensions enable "$uuid" 2>/dev/null
      echo "  enabled (already present): $label"
      return 0
    fi
  done
  if [[ -z "$GEXT" ]]; then
    echo "  ! $label: gext unavailable and not pre-installed — skipped"
    return 0
  fi
  for uuid in "$@"; do
    if "$GEXT" install "$uuid" >/dev/null 2>&1; then
      "$GEXT" enable "$uuid" >/dev/null 2>&1
      echo "  installed: $label ($uuid)"
      return 0
    fi
  done
  echo "  ! $label: no compatible version for this GNOME release — skipped"
  return 0
}

# --- Group 2: requested extensions (with fallbacks where a fork exists) ---
install_ego "Caffeine"                     "caffeine@patapon.info"
install_ego "Clipboard Indicator"          "clipboard-indicator@tudmotu.com"
install_ego "Desktop Icons (NG)"           "ding@rastersoft.com" "desktop-icons@csoriano"
install_ego "Impatience"                   "impatience@gfxmonk.net"
install_ego "Lock Keys"                    "lockkeys@vaina.lt"
install_ego "OpenWeather"                  "openweather-extension@jenslody.de" "openweatherrefined@penguin-teal.github.io"
install_ego "Refresh Wifi Connections"     "refresh-wifi@kgshank.net"
install_ego "Sound In/Out Device Chooser"  "sound-output-device-chooser@kgshank.net"
install_ego "Vitals"                       "Vitals@CoreCoding.com"

# --- A few extras worth having on a dev workstation ---
install_ego "Tiling Shell"                 "tilingshell@ferrarodomenico.com"   # keyboard window tiling
install_ego "Blur My Shell"                "blur-my-shell@aunetx"              # nicer panel/overview look
install_ego "Alphabetical App Grid"        "AlphabeticalAppGrid@stuarthayhurst" # sort the app grid A–Z
install_ego "Just Perfection"              "just-perfection-desktop@just-perfection" # fine-grained shell tweaks

echo "GNOME tweaks applied"
echo "NOTE: log out and back in for newly installed extensions to load,"
echo "      then fine-tune them in the Extension Manager app."