#!/usr/bin/env bash
set -euo pipefail

# plasma-dockctl - desinstalacion completa del widget y del backend

systemctl --user disable --now dockctl 2>/dev/null || true
rm -rf "${HOME}/.local/share/plasma/plasmoids/org.gato99.dockctl"
rm -f "${HOME}/.config/systemd/user/dockctl.service"
rm -f "${HOME}/.local/share/icons/hicolor/scalable/apps/docker.svg"
systemctl --user daemon-reload

echo "Listo: widget y servicio eliminados."
echo "Quedan conservados: ~/.local/share/dockctl (backend) y ~/.config/dockctl (config)."
echo "Borrarlos con: rm -rf ~/.local/share/dockctl ~/.config/dockctl"