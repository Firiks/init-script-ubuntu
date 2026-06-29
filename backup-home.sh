#!/bin/bash
# Back up a user's home directory to a timestamped, compressed tar archive.
#
# Usage:
#   ./backup-home.sh [destination_dir]
#   sudo ./backup-home.sh [destination_dir]      # backs up the invoking user's home
#   destination_dir defaults to ~/Backups
#
# The archive stores paths relative to /home, e.g. "michal/.bashrc", so restoring
# to /home recreates /home/<user>/...
#
# ─── Restore / extract ────────────────────────────────────────────────────────
#   List contents (no extraction):
#     tar -tzvf home-backup-USER-YYYYMMDD-HHMMSS.tar.gz
#
#   Restore in place (recreates /home/<user>/...; overwrites existing files):
#     sudo tar -xzvpf home-backup-USER-YYYYMMDD-HHMMSS.tar.gz -C /home
#
#   Extract somewhere safe to cherry-pick files instead:
#     mkdir -p /tmp/restore
#     tar -xzvf home-backup-USER-YYYYMMDD-HHMMSS.tar.gz -C /tmp/restore
#
#   Extract a single file/dir (path as shown by -t, e.g. michal/.ssh/config):
#     tar -xzvf home-backup-USER-YYYYMMDD-HHMMSS.tar.gz -C /tmp/restore michal/.ssh/config
#
#   (-p preserves permissions/ownership; use sudo when restoring to /home.)
# ──────────────────────────────────────────────────────────────────────────────

set -uo pipefail   # NOT -e: tar returns 1 on "file changed while reading", which is non-fatal

# Resolve the target user even when run via sudo
USER_NAME="${SUDO_USER:-$USER}"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
if [[ -z "$HOME_DIR" || ! -d "$HOME_DIR" ]]; then
  echo "Could not resolve home directory for user '$USER_NAME'." >&2
  exit 1
fi

PARENT="$(dirname "$HOME_DIR")"     # e.g. /home
BASE="$(basename "$HOME_DIR")"      # e.g. michal
DEST_DIR="${1:-$HOME_DIR/Backups}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="${DEST_DIR}/home-backup-${BASE}-${TIMESTAMP}.tar.gz"

mkdir -p "$DEST_DIR"

# Skip caches, trash, VM images and regenerable build dirs to keep the archive lean.
# Anchored patterns ("$BASE/...") match top-level only; "*/..." patterns match at any depth.
EXCLUDES=(
  "--exclude=$BASE/Backups"
  "--exclude=$BASE/.cache"
  "--exclude=$BASE/.local/share/Trash"
  "--exclude=$BASE/snap"
  "--exclude=$BASE/.var/app/*/cache"
  "--exclude=*/node_modules"
  "--exclude=*/vendor"
  "--exclude=*/.venv"
  "--exclude=*/__pycache__"
  "--exclude=*/.gradle"
  "--exclude=*/target"
  "--exclude=*.iso"
  "--exclude=*.img"
)
# If the destination is inside the home dir, exclude it RELATIVE to the archive root.
# tar matches excludes against relative member names ("user/..."), so an absolute
# --exclude=$DEST_DIR never matches — a custom in-home dest would archive itself.
case "$DEST_DIR" in
  "$HOME_DIR"/*) EXCLUDES+=("--exclude=$BASE/${DEST_DIR#"$HOME_DIR"/}") ;;
esac

echo "Backing up ${HOME_DIR}"
echo "  -> ${ARCHIVE}"

tar -czpf "$ARCHIVE" "${EXCLUDES[@]}" -C "$PARENT" "$BASE"
rc=$?

if [[ $rc -eq 0 ]]; then
  echo "Backup complete: $(du -h "$ARCHIVE" | cut -f1)  ${ARCHIVE}"
elif [[ $rc -eq 1 ]]; then
  echo "Backup complete (some files changed during read — normal for a live home): $(du -h "$ARCHIVE" | cut -f1)  ${ARCHIVE}"
else
  echo "tar failed with exit code $rc" >&2
  exit $rc
fi
