#!/usr/bin/env bash
set -euo pipefail

# Genera el paquete instalable del widget: dist/org.gato99.dockctl.plasmoid (ZIP)
cd "$(dirname "${BASH_SOURCE[0]}")"

mkdir -p dist
rm -f dist/org.gato99.dockctl.plasmoid

cd plasmoid
zip -qr ../dist/org.gato99.dockctl.plasmoid metadata.json contents

cd ..
echo "paquete generado: dist/org.gato99.dockctl.plasmoid"
echo "instalar (GUI):  panel -> Añadir widgets -> Instalar desde archivo local..."
echo "instalar (CLI):  kpackagetool6 -t Plasma/Applet -i dist/org.gato99.dockctl.plasmoid"