#!/usr/bin/env bash
# Mirror refresh with optional full upgrade prompt
# By GrandBIRDLizard

set -euo pipefail

# -------------------------------------------------------------------
# Config
# -------------------------------------------------------------------

ARCH_MIRRORLIST="/etc/pacman.d/mirrorlist"
EOS_MIRRORLIST="/etc/pacman.d/endeavouros-mirrorlist"

BACKUP_DIR="/var/backups/pacman-mirrorlists"

ARCH_BACKUP="${BACKUP_DIR}/mirrorlist.last"
EOS_BACKUP="${BACKUP_DIR}/endeavouros-mirrorlist.last"

ARCH_BACKUP_NOTE="${BACKUP_DIR}/mirrorlist.last.README"
EOS_BACKUP_NOTE="${BACKUP_DIR}/endeavouros-mirrorlist.last.README"

TIMESTAMP="$(date '+%Y-%m-%d')"

TMP_ARCH="$(mktemp)"
TMP_EOS="$(mktemp)"

cleanup() {
  rm -f "$TMP_ARCH" "$TMP_EOS"
}
trap cleanup EXIT

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------

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

dot_pause() {
  printf '.'
  sleep 1
  printf '.'
  sleep 1
  printf '.\n'
}

prompt_yes_no() {
  local prompt="$1"
  local reply

  while true; do
    read -r -p "$prompt [y/n]: " reply
    case "${reply,,}" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *)     echo "Please answer y or n." ;;
    esac
  done
}

# -------------------------------------------------------------------
# Safety checks
# -------------------------------------------------------------------

[[ "${EUID}" -eq 0 ]] || die "This script must be run as root. Use: sudo $0"
command -v rate-mirrors >/dev/null 2>&1 || die "rate-mirrors is not installed."
command -v pacman >/dev/null 2>&1 || die "pacman not found."

mkdir -p "$BACKUP_DIR"

info "Starting mirror refresh at: $TIMESTAMP"

# -------------------------------------------------------------------
# Rotating backups (single-file backups, no pile-up)
# -------------------------------------------------------------------

if [[ -f "$ARCH_MIRRORLIST" ]]; then
  cp -f "$ARCH_MIRRORLIST" "$ARCH_BACKUP"
  cat > "$ARCH_BACKUP_NOTE" <<EOF
This file is a rotating backup of:
  $ARCH_MIRRORLIST

Behavior:
  - This backup is overwritten on each script run
  - Backups do NOT pile up

Last backup timestamp:
  $TIMESTAMP
EOF
  ok "Backed up Arch mirrorlist -> $ARCH_BACKUP"
fi

if [[ -f "$EOS_MIRRORLIST" ]]; then
  cp -f "$EOS_MIRRORLIST" "$EOS_BACKUP"
  cat > "$EOS_BACKUP_NOTE" <<EOF
This file is a rotating backup of:
  $EOS_MIRRORLIST

Behavior:
  - This backup is overwritten on each script run
  - Backups do NOT pile up

Last backup timestamp:
  $TIMESTAMP
EOF
  ok "Backed up EndeavourOS mirrorlist -> $EOS_BACKUP"
fi

dot_pause

# -------------------------------------------------------------------
# Generate fresh mirrorlists (no country restriction)
# -------------------------------------------------------------------

info "Ranking Arch mirrors (best available, no country restriction)..."
rate-mirrors \
  --protocol https \
  --max-delay 7200 \
  --allow-root \
  arch > "$TMP_ARCH"

info "Ranking EndeavourOS mirrors (best available, no country restriction)..."
rate-mirrors \
  --protocol https \
  --allow-root \
  endeavouros > "$TMP_EOS"

dot_pause

# -------------------------------------------------------------------
# Install fresh mirrorlists
# -------------------------------------------------------------------

install -m 644 "$TMP_ARCH" "$ARCH_MIRRORLIST"
install -m 644 "$TMP_EOS" "$EOS_MIRRORLIST"

ok "Installed new Arch mirrorlist        -> $ARCH_MIRRORLIST"
ok "Installed new EndeavourOS mirrorlist -> $EOS_MIRRORLIST"

dot_pause

# -------------------------------------------------------------------
# Advise before upgrade
# -------------------------------------------------------------------

echo
warn "Before running a full upgrade, check for manual intervention notices."
echo "    Arch Linux News:        https://archlinux.org/news/"
echo "    EndeavourOS News/Forum: https://forum.endeavouros.com/"
echo
warn "Because mirrorlists changed, a full upgrade should use: pacman -Syyu"
echo "    -yy forces a full database refresh against the NEW mirrors"
echo "    This helps avoid stale metadata / partial-sync issues."
echo

# -------------------------------------------------------------------
# Optional full refresh + upgrade
# -------------------------------------------------------------------

if prompt_yes_no "Run pacman -Syyu now?"; then
  info "Running pacman -Syyu ..."
  pacman -Syyu
  ok "System upgrade complete."

  echo
  warn "Reboot is NOT always required."
  echo "    Reboot is recommended if the upgrade included:"
  echo "      - kernel packages"
  echo "      - microcode (amd-ucode / intel-ucode)"
  echo "      - systemd / glibc"
  echo "      - nvidia or other kernel module / graphics stack updates"
else
  warn "Skipped pacman -Syyu."
  echo "    When ready, run:"
  echo "    sudo pacman -Syyu"
fi

echo
ok "Done."
