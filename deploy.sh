#!/bin/bash
# Build + sideload the VK Roku app. Relay URL/key come from macOS Keychain, never from git.
#   ./deploy.sh            package only (vkroku.zip)
#   ./deploy.sh install    package and install on the TV (takes over the TV screen!)
set -euo pipefail
cd "$(dirname "$0")"
TV=${TV:-192.168.0.3}
# RELAY / RELAY_KEY / DEV_PASS can be passed as env vars; otherwise they are read from the macOS Keychain
RELAY=${RELAY:-$(security find-generic-password -s vk-roku-relay-url -w)}
KEY=${RELAY_KEY:-$(security find-generic-password -s vk-roku-relay-key -w)}
printf 'function relayDefault() as string\n    return "%s/%s/"\nend function\n' "$RELAY" "$KEY" > components/Config.brs
rm -f vkroku.zip && zip -qr vkroku.zip manifest source components images
echo "packaged vkroku.zip"
if [ "${1:-}" = install ]; then
  PASS=${DEV_PASS:-$(security find-generic-password -s vk-roku-dev-installer -w)}
  curl -s -m 90 --digest -u "rokudev:$PASS" -F mysubmit=Install -F archive=@vkroku.zip "http://$TV/plugin_install" \
    | grep -oE "Install Success|Identical|Failure[^<]*|compile error[^<]*" | head -3
fi
