#!/usr/bin/env bash
set -euo pipefail

# plasma-dockctl - actualiza el widget desde el repo
# Uso: ./update.sh                     -> widget + icono + regenera dist/ + reinicia plasmashell
#      --no-dist    -> no regenera los paquetes de dist/
#      --backend    -> ademas actualiza el backend y reinicia el servicio
#      --release    -> ademas sube/actualiza los assets en la release GitHub v<version>
#      SKIP_PLASMA_RESTART=1 ./update.sh -> copia sin reiniciar

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ID="org.gato99.dockctl"

VERSION="$(cat "${DIR}/VERSION" 2>/dev/null || true)"
if [ -z "${VERSION}" ]; then
    VERSION="$(git -C "${DIR}" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "1.0")"
fi

PLASMOID_DEST="${HOME}/.local/share/plasma/plasmoids"
PLASMOID_DIR="${PLASMOID_DEST}/${APP_ID}"
BACKEND_DIR="${HOME}/.local/share/dockctl"

UPDATE_BACKEND=0
REGEN_DIST=1
UPDATE_RELEASE=0
for arg in "$@"; do
    case "${arg}" in
        --backend) UPDATE_BACKEND=1 ;;
        --no-dist) REGEN_DIST=0 ;;
        --release) UPDATE_RELEASE=1 ;;
        *) echo "Opcion desconocida: ${arg}" >&2; exit 1 ;;
    esac
done

echo "==> Widget  ->  ${PLASMOID_DIR}"
mkdir -p "${PLASMOID_DEST}"
rm -rf "${PLASMOID_DIR}"
cp -r "${DIR}/plasmoid" "${PLASMOID_DIR}"

echo "==> Icono de tema (selector de widgets)"
ICON_DIR="${HOME}/.local/share/icons/hicolor/scalable/apps"
mkdir -p "${ICON_DIR}"
cp "${DIR}/plasmoid/contents/images/docker.svg" "${ICON_DIR}/docker.svg"
gtk-update-icon-cache -f -q "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true
rm -f "${HOME}/.cache/icon-cache.kcache" 2>/dev/null || true

if [ "${UPDATE_BACKEND}" = "1" ]; then
    echo "==> Backend ->  ${BACKEND_DIR}"
    mkdir -p "${BACKEND_DIR}"
    cp "${DIR}/backend/backend.py" "${BACKEND_DIR}/backend.py"
    cp "${DIR}/backend/test_backend.py" "${BACKEND_DIR}/test_backend.py"
    systemctl --user restart dockctl
    echo "    servicio dockctl reiniciado"
fi

if [ "${REGEN_DIST}" = "1" ]; then
    echo "==> Paquetes de distribucion  (v${VERSION})"
    "${DIR}/build.sh"
    tar --exclude=.git --exclude=dist --exclude=.gitignore \
        -czf "${DIR}/dist/plasma-dockctl-v${VERSION}.tar.gz" -C "${DIR}" .
    (cd "${DIR}/.." && zip -qr "${DIR}/dist/plasma-dockctl-v${VERSION}.zip" \
        "$(basename "${DIR}")" \
        -x "$(basename "${DIR}")/.git/*" -x "$(basename "${DIR}")/dist/*" \
        -x "$(basename "${DIR}")/.gitignore")
    echo "    regenerados org.gato99.dockctl.plasmoid y plasma-dockctl-v${VERSION}.tar.gz/.zip"
fi

if [ "${UPDATE_RELEASE}" = "1" ]; then
    echo "==> Release GitHub  v${VERSION}"
    if [ "${REGEN_DIST}" != "1" ]; then
        echo "    (!) --release requiere regenerar dist/ primero (quita --no-dist)" >&2
        exit 1
    fi
    if gh release view "v${VERSION}" >/dev/null 2>&1; then
        gh release upload "v${VERSION}" \
            "${DIR}/dist/org.gato99.dockctl.plasmoid" \
            "${DIR}/dist/plasma-dockctl-v${VERSION}.tar.gz" \
            "${DIR}/dist/plasma-dockctl-v${VERSION}.zip" --clobber
        echo "    assets actualizados en la release v${VERSION}"
    else
        gh release create "v${VERSION}" --title "v${VERSION}" \
            "${DIR}/dist/org.gato99.dockctl.plasmoid" \
            "${DIR}/dist/plasma-dockctl-v${VERSION}.tar.gz" \
            "${DIR}/dist/plasma-dockctl-v${VERSION}.zip"
        echo "    release v${VERSION} creada"
    fi
fi

if [ "${SKIP_PLASMA_RESTART:-0}" != "1" ]; then
    read -r -p "Reiniciar plasmashell para que el widget actualizado quede visible? [s/N] " consulta
    case "${consulta}" in
        [sSyY]|[sS][iI]|[yY][eE][sS])
            kquitapp6 plasmashell 2>/dev/null || true
            sleep 2
            nohup /usr/bin/plasmashell >/dev/null 2>&1 &
            disown || true
            echo "Plasmashell reiniciado."
            ;;
        *)
            echo "El widget se actualizara al siguiente reinicio de plasmashell."
            ;;
    esac
fi

echo
echo "Listo. El widget ${APP_ID} esta actualizado (v${VERSION})."