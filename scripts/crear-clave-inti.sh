#!/bin/bash
# Crea la clave con la que firmas los paquetes de Inti OS (una sola vez).
#
# La clave PRIVADA se queda en tu llavero de GPG (~/.gnupg) y no se sube a
# ningún sitio: guarda una copia de seguridad (te lo recuerda al final). Si
# se pierde, no podrás publicar actualizaciones que los equipos acepten; si
# alguien la roba, podría publicar actualizaciones falsas.
#
# Lo que sí se guarda en el proyecto es la clave PÚBLICA y su huella
# (paquetes/inti-keyring), que viajan en el paquete inti-keyring.
set -euo pipefail
raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destino="${raiz}/paquetes/inti-keyring"
nombre="${1:-Inti OS - firma de paquetes}"

if [[ -s "${destino}/inti-trusted" ]]; then
  echo "Ya hay una clave de Inti: $(cut -d: -f1 "${destino}/inti-trusted")"
  echo "Para usarla: export INTI_CLAVE=$(cut -d: -f1 "${destino}/inti-trusted")"
  exit 0
fi

echo "Se va a crear la clave de firma de Inti OS."
echo "GPG te pedirá una contraseña para protegerla: elige una buena y no la olvides."
gpg --quick-generate-key "${nombre}" rsa4096 sign 3y
huella="$(gpg --list-secret-keys --with-colons "${nombre}" | awk -F: '/^fpr:/ {print $10; exit}')"
[[ -n "${huella}" ]] || { echo "No se encontró la clave creada" >&2; exit 1; }

gpg --armor --export "${huella}" > "${destino}/inti.gpg"
printf '%s:4:\n' "${huella}" > "${destino}/inti-trusted"
: > "${destino}/inti-revoked"

echo
echo "Clave creada: ${huella}"
echo "Pública guardada en paquetes/inti-keyring (esa sí va en el proyecto)."
echo
echo "Para firmar al construir el repositorio:"
echo "  export INTI_CLAVE=${huella}"
echo
echo "MUY IMPORTANTE - copia de seguridad de la clave privada (en un USB, no en GitHub):"
echo "  gpg --export-secret-keys --armor ${huella} > inti-clave-privada.asc"
