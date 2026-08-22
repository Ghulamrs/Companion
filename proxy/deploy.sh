#!/usr/bin/env bash
#
# Copies the proxy to the server. Never touches /var/www/html itself: everything
# lives in the /ai subdirectory, so the Morningwalk endpoints beside it are not
# in the blast radius.
#
# It deliberately does not carry the config file. That is created once, by hand,
# outside the document root — see README.md. Nothing in this repository ever
# holds a credential.

set -euo pipefail

HOST="${COMPANION_HOST:-morningwalk}"
REMOTE_DIR="${COMPANION_REMOTE_DIR:-/var/www/html/ai}"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "Deploying to ${HOST}:${REMOTE_DIR}"

# The document root is owned by apache, so rsync needs sudo on the far side.
# No --delete: this directory is not the only thing that may ever live there.
rsync -av --rsync-path="sudo rsync" \
      "${HERE}/public/" "${HOST}:${REMOTE_DIR}/"

ssh "${HOST}" "
  set -e
  sudo chown -R apache:apache '${REMOTE_DIR}'
  sudo chmod 755 '${REMOTE_DIR}'
  sudo find '${REMOTE_DIR}' -type f -exec chmod 644 {} +
  # SELinux is permissive here, but a correct label costs nothing and means
  # switching it to enforcing later does not silently break this.
  command -v restorecon >/dev/null && sudo restorecon -R '${REMOTE_DIR}' || true
  ls -la '${REMOTE_DIR}'
"

echo
echo "Deployed. The endpoint is <https-host>/ai/v1/messages"
echo "It will answer 500 until /var/www/secure/companion-config.php exists."
