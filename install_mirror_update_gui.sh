#!/usr/bin/env bash
# Arch & EOS Mirror Assistant installer
# By GrandBIRDLizard

set -euo pipefail

# User paths (auto-detected)
USER_NAME="$(id -un)"
USER_HOME="${HOME}"

LOCAL_BIN="${USER_HOME}/.local/bin"
USER_SYSTEMD_DIR="${USER_HOME}/.config/systemd/user"
DESKTOP_DIR="${USER_HOME}/.local/share/applications"

GUIDED_GUI="${LOCAL_BIN}/update_all_mirrors_guided_gui.sh"
LOGIN_GUI="${LOCAL_BIN}/update_all_mirrors_login_gui.sh"
USER_SERVICE="${USER_SYSTEMD_DIR}/update-all-mirrors-login-gui.service"
DESKTOP_FILE="${DESKTOP_DIR}/update-all-mirrors-guided.desktop"

# Backend assumptions
WORKER_SCRIPT="/usr/local/bin/update_all_mirrors_weekly.sh"
CLI_FALLBACK="/usr/local/bin/update_all_mirrors_prompt_upgrade.sh"

# Helpers
info() {
  printf '[*] %s\n' "$*"
}

ok() {
  printf '[+] %s\n' "$*"
}

warn() {
  printf '[!] %s\n' "$*"
}

die() {
  printf '[-] %s\n' "$*" >&2
  exit 1
}

# Sanity checks
[[ -x "$WORKER_SCRIPT" ]] || die "Missing worker script: $WORKER_SCRIPT"

if [[ ! -x "$CLI_FALLBACK" ]]; then
  warn "CLI fallback script not found: $CLI_FALLBACK"
  warn "Continuing anyway (GUI wrappers will still work)."
fi

command -v systemctl >/dev/null 2>&1 || die "systemctl not found."
command -v update-desktop-database >/dev/null 2>&1 || warn "update-desktop-database not found (desktop cache refresh will be skipped)."
command -v kdialog >/dev/null 2>&1 || warn "kdialog not found right now (manual GUI wrapper will need it at runtime)."
command -v pkexec >/dev/null 2>&1 || warn "pkexec not found right now (manual GUI wrapper will need it at runtime)."
command -v notify-send >/dev/null 2>&1 || warn "notify-send not found right now (login GUI wrapper will need it at runtime)."

# Create directories
info "Creating user directories..."
mkdir -p "$LOCAL_BIN"
mkdir -p "$USER_SYSTEMD_DIR"
mkdir -p "$DESKTOP_DIR"

# Write manual guided GUI wrapper (uses pkexec)
info "Writing manual guided GUI wrapper..."
cat > "$GUIDED_GUI" <<'EOF'
#!/usr/bin/bash
# Arch & EOS Mirror Assistant manual GUI
# Uses kdialog for dialogs and pkexec for root actions
# By GrandBIRDLizard

set -euo pipefail

# Config
APP_TITLE="Arch + EOS Mirror Assistant"
WORKER_SCRIPT="/usr/local/bin/update_all_mirrors_weekly.sh"
PACMAN_BIN="/usr/bin/pacman"
FIREFOX_BIN="/usr/bin/firefox"

ARCH_NEWS_URL="https://archlinux.org/news/"
EOS_NEWS_URL="https://forum.endeavouros.com/"

# Helpers
die_gui() {
  kdialog --title "$APP_TITLE" --error "$1"
  exit 1
}

info_gui() {
  kdialog --title "$APP_TITLE" --icon system-software-update --msgbox "$1"
}

open_news_menu() {
  local choice

  choice="$(kdialog \
    --title "$APP_TITLE" \
    --menu "Before upgrading, you may want to open release / intervention notices first." \
    "arch" "Open Arch Linux News in Firefox" \
    "eos" "Open EndeavourOS News / Forum in Firefox" \
    "skip" "Continue without opening anything")" || return 0

  case "$choice" in
    arch)
      "$FIREFOX_BIN" "$ARCH_NEWS_URL" >/dev/null 2>&1 &
      ;;
    eos)
      "$FIREFOX_BIN" "$EOS_NEWS_URL" >/dev/null 2>&1 &
      ;;
    skip|"")
      ;;
  esac
}

# Safety checks
command -v kdialog >/dev/null 2>&1 || {
  echo "kdialog is not installed." >&2
  exit 1
}

command -v pkexec >/dev/null 2>&1 || die_gui "pkexec is not installed."
[[ -x "$WORKER_SCRIPT" ]] || die_gui "Worker script not found or not executable:\n$WORKER_SCRIPT"
[[ -x "$PACMAN_BIN" ]] || die_gui "pacman not found at:\n$PACMAN_BIN"
[[ -x "$FIREFOX_BIN" ]] || die_gui "Firefox not found at:\n$FIREFOX_BIN"

# Intro / manual intervention reminder
info_gui "This tool will refresh Arch + EndeavourOS mirrors first.

Before a full system upgrade on Arch / EndeavourOS, check for manual intervention notices.

You will now be offered quick links for:
- Arch Linux News
- EndeavourOS News / Forum"

open_news_menu

# Ask to refresh mirrors
if ! kdialog --title "$APP_TITLE" --warningyesno "Refresh Arch + EndeavourOS mirrors now?"; then
  kdialog --title "$APP_TITLE" --sorry "Mirror refresh canceled."
  exit 0
fi

kdialog --title "$APP_TITLE" --passivepopup "Refreshing mirrors..." 4 >/dev/null 2>&1 || true

# Run the root worker
if pkexec "$WORKER_SCRIPT"; then
  info_gui "Mirror refresh completed successfully.

Your mirrorlists were updated.

Because mirrors just changed, the recommended upgrade command is:
sudo pacman -Syyu"
else
  die_gui "Mirror refresh failed.

Check:
- ~/.local/state/update-all-mirrors/last_run.log
- /var/lib/update-all-mirrors-weekly/last_run.status"
fi

# Ask whether to run a full upgrade now
if kdialog --title "$APP_TITLE" --warningyesno "Mirrors were refreshed successfully.

Do you want to run a full upgrade now?

Recommended after mirror changes:
sudo pacman -Syyu"; then

  if kdialog --title "$APP_TITLE" --yesno "Open Arch / EndeavourOS news pages in Firefox before upgrading?"; then
    open_news_menu
  fi

  kdialog --title "$APP_TITLE" --passivepopup "Running pacman -Syyu..." 4 >/dev/null 2>&1 || true

  if pkexec "$PACMAN_BIN" -Syyu; then
    info_gui "System upgrade completed.

Reboot is NOT always required.

Reboot is recommended if the upgrade included:
- kernel packages
- microcode (amd-ucode / intel-ucode)
- systemd / glibc
- nvidia or other kernel module / graphics stack updates"
  else
    die_gui "The system upgrade failed or was canceled.

Resolve any pacman issues before retrying."
  fi
else
  info_gui "Upgrade skipped.

When you are ready, run:

sudo pacman -Syyu"
fi

exit 0
EOF

chmod +x "$GUIDED_GUI"
ok "Wrote: $GUIDED_GUI"

# Write weekly login GUI wrapper (uses sudo + exact NOPASSWD rule)
info "Writing weekly login GUI wrapper..."
cat > "$LOGIN_GUI" <<'EOF'
#!/usr/bin/bash
# Weekly mirror refresh at login (GUI wrapper for Plasma)
# Runs once per ISO week, only when user logs in
# Uses sudo for silent root execution (requires exact NOPASSWD rule)
# By GrandBIRDLizard

set -euo pipefail

# Config
WORKER_SCRIPT="/usr/local/bin/update_all_mirrors_weekly.sh"

STAMP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/update-all-mirrors"
STAMP_FILE="${STAMP_DIR}/last_run_week"
LOG_FILE="${STAMP_DIR}/last_run.log"

mkdir -p "$STAMP_DIR"

CURRENT_WEEK="$(date '+%G-%V')"

# Helpers
notify_ok() {
  notify-send \
    "Arch + EOS Mirror Assistant" \
    "Arch + EndeavourOS mirrors were refreshed successfully this week." \
    --icon=system-software-update
}

notify_fail() {
  notify-send \
    "Arch + EOS Mirror Assistant" \
    "Mirror refresh failed. Check logs or status files." \
    --icon=dialog-error
}

# Safety checks
command -v notify-send >/dev/null 2>&1 || {
  echo "notify-send is not installed." >&2
  exit 1
}

command -v sudo >/dev/null 2>&1 || {
  echo "sudo is not installed." >&2
  exit 1
}

[[ -x "$WORKER_SCRIPT" ]] || {
  echo "Worker script missing or not executable: $WORKER_SCRIPT" >&2
  exit 1
}

# Skip if already ran this ISO week
if [[ -f "$STAMP_FILE" ]] && [[ "$(cat "$STAMP_FILE")" == "$CURRENT_WEEK" ]]; then
  printf '%s :: skipped (already ran this week)\n' "$(date '+%F %T')" >> "$LOG_FILE"
  exit 0
fi

# Run root worker silently via sudo
if sudo "$WORKER_SCRIPT" >> "$LOG_FILE" 2>&1; then
  printf '%s' "$CURRENT_WEEK" > "$STAMP_FILE"
  printf '%s :: success\n' "$(date '+%F %T')" >> "$LOG_FILE"
  notify_ok
else
  printf '%s :: FAILED\n' "$(date '+%F %T')" >> "$LOG_FILE"
  notify_fail
  exit 1
fi
EOF

chmod +x "$LOGIN_GUI"
ok "Wrote: $LOGIN_GUI"

# Write user systemd service
info "Writing user systemd service..."
cat > "$USER_SERVICE" <<'EOF'
[Unit]
Description=Arch + EOS Mirror Assistant weekly mirror refresh at graphical login
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=oneshot
ExecStart=%h/.local/bin/update_all_mirrors_login_gui.sh
EOF

ok "Wrote: $USER_SERVICE"

# Write desktop launcher
info "Writing Plasma desktop launcher..."
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Arch + EOS Mirror Assistant
GenericName=Arch + EOS Mirror Assistant
Comment=Guided Arch and EndeavourOS mirror refresh with optional full upgrade
Exec=${GUIDED_GUI}
Icon=system-software-update
Terminal=false
Categories=System;Settings;Utility;
Keywords=arch;endeavouros;mirror;mirrors;pacman;update;
StartupNotify=true
EOF

ok "Wrote: $DESKTOP_FILE"

# Refresh desktop DB and enable service
if command -v update-desktop-database >/dev/null 2>&1; then
  info "Refreshing desktop database..."
  update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi

info "Reloading user systemd..."
systemctl --user daemon-reload

info "Enabling weekly login service..."
systemctl --user enable update-all-mirrors-login-gui.service >/dev/null

# Final summary
echo
ok "Install complete for user: $USER_NAME"
echo
echo "Installed files:"
echo "  $GUIDED_GUI"
echo "  $LOGIN_GUI"
echo "  $USER_SERVICE"
echo "  $DESKTOP_FILE"
echo
warn "IMPORTANT:"
echo "  The weekly login GUI uses:"
echo "    sudo /usr/local/bin/update_all_mirrors_weekly.sh"
echo
echo "  Make sure you added the exact visudo rule:"
echo "    $USER_NAME ALL=(root) NOPASSWD: /usr/local/bin/update_all_mirrors_weekly.sh"
echo
echo "Test the weekly login wrapper now:"
echo "  systemctl --user start update-all-mirrors-login-gui.service"
echo
echo "Launch the manual GUI now:"
echo "  $GUIDED_GUI"
echo
echo "Or from the Plasma app launcher:"
echo "  Arch + EOS Mirror Assistant"
