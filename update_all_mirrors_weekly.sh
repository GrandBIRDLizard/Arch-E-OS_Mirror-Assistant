#!/usr/bin/bash
#Arch & EOS Update Assistant 
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

STATUS_DIR="/var/lib/update-all-mirrors-weekly"
STATUS_FILE="${STATUS_DIR}/last_run.status"

TIMESTAMP="$(date '+%Y-%m-%d')"
RUNSTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

TMP_ARCH="$(mktemp)"
TMP_EOS="$(mktemp)"

cleanup() {
  rm -f "$TMP_ARCH" "$TMP_EOS"
}
trap cleanup EXIT

failure_handler() {
  mkdir -p "$STATUS_DIR"
  cat > "$STATUS_FILE" <<EOF
Last run attempt: $RUNSTAMP
Service context: update_all_mirrors_weekly.sh
Status: FAILED
Suggested checks:
  - journalctl --user -u update-all-mirrors-login.service -n 100
  - sudo /usr/local/bin/update_all_mirrors_weekly.sh
EOF
}
trap failure_handler ERR

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------

info() {
  printf '[*] %s\n' "$*"
}

ok() {
  printf '[+] %s\n' "$*"
}

die() {
  printf '[-] %s\n' "$*" >&2
  exit 1
}

# -------------------------------------------------------------------
# Safety checks
# -------------------------------------------------------------------

[[ "${EUID}" -eq 0 ]] || die "This script must be run as root."
command -v rate-mirrors >/dev/null 2>&1 || die "rate-mirrors is not installed."

mkdir -p "$BACKUP_DIR"
mkdir -p "$STATUS_DIR"

info "Starting weekly mirror refresh at: $RUNSTAMP"

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

# -------------------------------------------------------------------
# Generate fresh mirrorlists
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

# -------------------------------------------------------------------
# Install fresh mirrorlists
# -------------------------------------------------------------------

install -m 644 "$TMP_ARCH" "$ARCH_MIRRORLIST"
install -m 644 "$TMP_EOS" "$EOS_MIRRORLIST"

ok "Installed new Arch mirrorlist        -> $ARCH_MIRRORLIST"
ok "Installed new EndeavourOS mirrorlist -> $EOS_MIRRORLIST"

# -------------------------------------------------------------------
# Success status
# -------------------------------------------------------------------

cat > "$STATUS_FILE" <<EOF
Last successful run: $RUNSTAMP
Service context: update_all_mirrors_weekly.sh
Arch mirrorlist: $ARCH_MIRRORLIST
EndeavourOS mirrorlist: $EOS_MIRRORLIST
Status: SUCCESS

Reminder:
  Before your next full upgrade, check:
    - https://archlinux.org/news/
    - https://forum.endeavouros.com/

After mirror changes, use:
  sudo pacman -Syyu
EOF

ok "Weekly mirror refresh complete."
