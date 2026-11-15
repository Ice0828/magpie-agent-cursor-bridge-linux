#!/bin/bash
set -euo pipefail

PACKAGE_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
COMMAND="${1:-setup}"

find_runtime() {
  if command -v node >/dev/null 2>&1; then
    command -v node
    return 0
  fi
  # Magpie embedded bun cache
  for bun_candidate in "$HOME"/.cache/magpie/bun/*/magpie-bun "$HOME"/.cache/magpie/bun/*/bun; do
    if [ -x "$bun_candidate" ]; then
      echo "$bun_candidate"
      return 0
    fi
  done
  if command -v bun >/dev/null 2>&1; then
    command -v bun
    return 0
  fi
  echo "Error: Neither node nor bun runtime was found." >&2
  exit 1
}

RUNTIME="$(find_runtime)"

SERVICE_UNIT="local.magpie.cursor-bridge"

case "$COMMAND" in
  setup|install)
    echo "==> Setting up cursor-magpie-bridge-linux..."
    "$RUNTIME" "$PACKAGE_DIR/install.js" setup
    ;;
  dev)
    echo "==> Setting up cursor-magpie-bridge-linux in DEV mode (local binary preferred)..."
    CURSOR_BRIDGE_LOCAL_BIN=1 "$RUNTIME" "$PACKAGE_DIR/install.js" setup
    ;;
  status)
    "$RUNTIME" "$PACKAGE_DIR/install.js" status
    ;;
  uninstall|remove)
    echo "==> Uninstalling cursor-magpie-bridge-linux..."
    "$RUNTIME" "$PACKAGE_DIR/install.js" uninstall
    ;;
  start)
    systemctl --user start "$SERVICE_UNIT"
    ;;
  stop)
    systemctl --user stop "$SERVICE_UNIT"
    ;;
  restart)
    systemctl --user restart "$SERVICE_UNIT"
    ;;
  logs)
    journalctl --user -u "$SERVICE_UNIT" -f
    ;;
  *)
    echo "Usage: $0 [setup|dev|status|start|stop|restart|logs|uninstall]"
    exit 1
    ;;
esac
