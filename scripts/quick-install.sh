#!/bin/bash
# Homelab Quick Install - One-liner script
# Uso: curl -fsSL https://raw.githubusercontent.com/andonisan/nas/main/scripts/quick-install.sh | bash

set -euo pipefail

REPO_URL="https://github.com/andonisan/nas.git"
INSTALL_PATH="/srv/homelab"
SCRIPT_URL="https://raw.githubusercontent.com/andonisan/nas/main/scripts/deploy-homelab.sh"

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}"
cat << "EOF"
 _   _                      _       _     
| | | | ___  _ __ ___   ___| | __ _| |__  
| |_| |/ _ \| '_ ` _ \ / _ \ |/ _` | '_ \ 
|  _  | (_) | | | | | |  __/ | (_| | |_) |
|_| |_|\___/|_| |_| |_|\___|_|\__,_|_.__/ 
                                         
Instalación Rápida - GitOps-lite
EOF
echo -e "${NC}"

echo -e "${BLUE}Descargando script de despliegue...${NC}"

# Descargar y ejecutar script principal
curl -fsSL "$SCRIPT_URL" -o /tmp/deploy-homelab.sh
chmod +x /tmp/deploy-homelab.sh

echo -e "${BLUE}Iniciando instalación...${NC}"
/tmp/deploy-homelab.sh "$@"

# Limpiar
rm -f /tmp/deploy-homelab.sh

echo -e "${GREEN}¡Instalación completada!${NC}"
echo
echo "Comandos útiles:"
echo "  $INSTALL_PATH/scripts/manage-homelab.sh status"
echo "  $INSTALL_PATH/scripts/manage-homelab.sh logs"
echo "  $INSTALL_PATH/scripts/manage-homelab.sh backup"
