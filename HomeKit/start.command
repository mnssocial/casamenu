#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if launchctl print "gui/$(id -u)/br.local.CasaMenu.bridge" >/dev/null 2>&1; then
  echo 'A ponte instalada já é gerenciada automaticamente pelo macOS.'
  exit 0
fi
runtime="${CASAMENU_NODE:-$PWD/runtime/bin/node}"
if [[ ! -x "$runtime" ]]; then runtime=$(command -v node || true); fi
if [[ -z "$runtime" ]]; then echo 'Instale Node.js 24 LTS antes de continuar.'; exit 1; fi
major=$("$runtime" -p 'process.versions.node.split(".")[0]')
if [[ "$major" != 22 && "$major" != 24 ]]; then echo 'Esta ponte exige Node.js 22 ou 24 LTS.'; exit 1; fi
export PATH="${runtime:h}:$PATH"
if [[ ! -d node_modules/homebridge ]]; then npm ci --no-audit --no-fund; fi
storage="${CASAMENU_BRIDGE_STORAGE:-$HOME/Library/Application Support/CasaMenu/homebridge-data}"
"$runtime" setup.mjs "$storage"
echo 'Ponte em execução. Abra http://127.0.0.1:8581 para concluir a configuração e ver o QR.'
echo 'Mantenha esta janela aberta. Ctrl+C encerra a ponte.'
exec "$runtime" node_modules/homebridge-config-ui-x/dist/bin/hb-service.js run -U "$storage" -P "$PWD/node_modules" --strict-plugin-resolution
