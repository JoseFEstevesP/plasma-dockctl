#!/usr/bin/env bash
set -euo pipefail

# plasma-dockctl - instalacion del widget Docker + backend HTTP
# Uso: ./install.sh   (opcional: SKIP_PLASMA_RESTART=1 ./install.sh)

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ID="org.gato99.dockctl"

PLASMOID_DEST="${HOME}/.local/share/plasma/plasmoids"
PLASMOID_DIR="${PLASMOID_DEST}/${APP_ID}"
BACKEND_DIR="${HOME}/.local/share/dockctl"
SERVICE_UNIT="${HOME}/.config/systemd/user/dockctl.service"
CONFIG_DIR="${HOME}/.config/dockctl"
CONFIG_FILE="${CONFIG_DIR}/config.ini"

echo "==> Widget  ->  ${PLASMOID_DIR}"
mkdir -p "${PLASMOID_DEST}"
rm -rf "${PLASMOID_DIR}"
cp -r "${DIR}/plasmoid" "${PLASMOID_DIR}"

echo "==> Icono de tema (para el selector de widgets)"
ICON_DIR="${HOME}/.local/share/icons/hicolor/scalable/apps"
mkdir -p "${ICON_DIR}"
cp "${DIR}/plasmoid/contents/images/docker.svg" "${ICON_DIR}/docker.svg"
gtk-update-icon-cache -f -q "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true
rm -f "${HOME}/.cache/icon-cache.kcache" 2>/dev/null || true

echo "==> Backend ->  ${BACKEND_DIR}"
mkdir -p "${BACKEND_DIR}"
cp "${DIR}/backend/backend.py" "${BACKEND_DIR}/backend.py"
cp "${DIR}/backend/test_backend.py" "${BACKEND_DIR}/test_backend.py"

echo "==> Servicio systemd (usuario)"
mkdir -p "$(dirname "${SERVICE_UNIT}")"
cp "${DIR}/systemd/dockctl.service" "${SERVICE_UNIT}"

echo "==> Configuracion"
mkdir -p "${CONFIG_DIR}"
if [ ! -f "${CONFIG_FILE}" ]; then
    printf '[server]\nport = 8427\nhost = 127.0.0.1\n' > "${CONFIG_FILE}"
    echo "    creado ${CONFIG_FILE}"
fi

systemctl --user daemon-reload
systemctl --user enable --now dockctl

echo
echo "Backend activo en 127.0.0.1:8427"

if [ "${SKIP_PLASMA_RESTART:-0}" != "1" ]; then
    read -r -p "Reiniciar plasmashell ahora para que el widget este disponible? [s/N] " consulta
    case "${consulta}" in
        [sSyY]|[sS][iI]|[yY][eE][sS])
            kquitapp6 plasmashell 2>/dev/null || true
            nohup /usr/bin/plasmashell >/dev/null 2>&1 &
            disown || true
            echo "Plasmashell reiniciado."
            ;;
        *)
            echo "Anade el widget manualmente: con plasmashell reiniciado aparecera 'Contenedores Docker'."
            ;;
    esac
fi

echo
echo "Listo. Anade el widget: clic derecho en la barra -> 'Anadir widgets' -> 'Contenedores Docker'."
echo "Pruebas del backend: python3 ${BACKEND_DIR}/test_backend.py"