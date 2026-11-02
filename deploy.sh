#!/bin/bash
# Build + sideload the VK Roku app. Relay URL/key come from macOS Keychain, never from git.
#   ./deploy.sh            package only (vkroku.zip)
#   ./deploy.sh install    package and install on the TV (takes over the TV screen!)
set -euo pipefail
cd "$(dirname "$0")"
TV=${TV:-192.168.0.3}
# RELAY / RELAY_KEY / DEV_PASS: env vars, else macOS Keychain. No relay = the TV talks to VK directly.
kc() { security find-generic-password -s "$1" -w 2>/dev/null || true; }
RELAY=${RELAY-$(kc vk-roku-relay-url)}
KEY=${RELAY_KEY-$(kc vk-roku-relay-key)}
BASE=""; [ -n "$RELAY" ] && BASE="$RELAY/$KEY/"
printf 'function relayDefault() as string\n    return "%s"\nend function\n' "$BASE" > components/Config.brs
rm -f vkroku.zip && zip -qr vkroku.zip manifest source components images
echo "packaged vkroku.zip"
if [ "${1:-}" = install ]; then
  PASS=${DEV_PASS:-$(kc vk-roku-dev-installer)}
  curl -s -m 90 --digest -u "rokudev:$PASS" -F mysubmit=Install -F archive=@vkroku.zip "http://$TV/plugin_install" \
    | grep -oE "Install Success|Identical|Failure[^<]*|compile error[^<]*" | head -3
fi
