#!/usr/bin/env bash
# Arch & EOS Mirror Assistant uninstaller
# By GrandBIRDLizard

set -euo pipefail

# User paths (auto-detected)
USER_NAME="$(id -un)"
USER_HOME="${HOME}"

GUIDED_GUI="${USER_HOME}/.local/bin/update_all_mirrors_guided_gui.sh"
LOGIN_GUI="${USER_HOME}/.local/bin/update_all_mirrors_login_gui.sh"
USER_SERVICE="${USER_HOME}/.config/systemd/user/update-all-mirrors-login-gui.service"
DESKTOP_FILE="${USER_HOME}/.local/share/applications/update-all-mirrors-guided.desktop"
DESKTOP_DIR="${USER_HOME}/.local/share/applications"

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

# Disable service first
info "Disabling user systemd service (if present)..."
systemctl --user disable update-all-mirrors-login-gui.service >/dev/null 2>&1 || true

# Remove files
info "Removing installed files..."
rm -f "$GUIDED_GUI"
rm -f "$LOGIN_GUI"
rm -f "$USER_SERVICE"
rm -f "$DESKTOP_FILE"

# Reload systemd and desktop DB
info "Reloading user systemd..."
systemctl --user daemon-reload

if command -v update-desktop-database >/dev/null 2>&1; then
  info "Refreshing desktop database..."
  update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi

# Final summary
echo
ok "Uninstall complete for user: $USER_NAME"
echo
echo "Removed:"
echo "  $GUIDED_GUI"
echo "  $LOGIN_GUI"
echo "  $USER_SERVICE"
echo "  $DESKTOP_FILE"
echo
warn "Backend root scripts were NOT removed:"
echo "  /usr/local/bin/update_all_mirrors_weekly.sh"
echo "  /usr/local/bin/update_all_mirrors_prompt_upgrade.sh"
echo
warn "Optional cleanup:"
echo "  If you no longer want silent weekly login runs, remove the visudo rule:"
echo "    $USER_NAME ALL=(root) NOPASSWD: /usr/local/bin/update_all_mirrors_weekly.sh"
