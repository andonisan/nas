#!/bin/bash
# Script para configurar/reconfigurar Homer Dashboard

set -euo pipefail

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Obtener dominio del .env
if [ -f .env ]; then
    DOMAIN=$(grep "HEIMDALL_DOMAIN=" .env | cut -d'=' -f2 | sed 's/dashboard\.//')
else
    error "Archivo .env no encontrado"
fi

log "Configurando Homer Dashboard para dominio: $DOMAIN"

# Función para configurar Homer
configure_homer() {
    if [ ! -f "configs/homer/config.yml" ]; then
        error "Archivo de configuración Homer no encontrado"
    fi
    
    # Crear backup del config original
    cp configs/homer/config.yml configs/homer/config.yml.backup
    
    # Aplicar configuración de dominio
    chmod +x configs/homer/configure.sh
    configs/homer/configure.sh configs/homer/config.yml "$DOMAIN"
    
    # Reiniciar Homer para cargar nueva configuración
    if docker compose ps homer | grep -q "running"; then
        log "Reiniciando Homer..."
        docker compose restart homer
    fi
    
    log "¡Homer configurado correctamente!"
    info "Accede a: http://dashboard.$DOMAIN"
}

# Función para mostrar servicios configurados
show_services() {
    echo
    info "=== SERVICIOS CONFIGURADOS EN HOMER ==="
    echo "🏠 Dashboard: http://dashboard.$DOMAIN"
    echo
    echo "📺 Core Services:"
    echo "  🎬 Jellyfin: http://jellyfin.$DOMAIN"
    echo "  🔄 Syncthing: http://sync.dashboard.$DOMAIN"
    echo
    echo "📸 Photos & Media:"
    echo "  📸 Immich: http://fotos.$DOMAIN"
    echo
    echo "📊 Monitoring:"
    echo "  📊 Netdata: http://metrics.$DOMAIN"
    echo "  ⏰ Uptime Kuma: http://status.$DOMAIN"
    echo "  📈 Grafana: http://grafana.$DOMAIN"
    echo
    echo "�️ Network & Security:"
    echo "  🛡️  AdGuard: http://adguard.$DOMAIN"
    echo "  🔐 Vault: http://vault.$DOMAIN"
    echo
    echo "⚙️ Management & Files:"
    echo "  🐳 Docker: http://docker.$DOMAIN"
    echo "  � Files: http://files.$DOMAIN"
    echo "  � Backup: http://backup.$DOMAIN"
    echo
    info "Servicios organizados por categorías con iconos modernos"
}

# Función de ayuda
show_help() {
    echo "Uso: $0 [opciones]"
    echo
    echo "Opciones:"
    echo "  configure    Configurar/reconfigurar Homer"
    echo "  reset        Resetear configuración a valores por defecto"
    echo "  show         Mostrar servicios configurados"
    echo "  edit         Editar configuración manualmente"
    echo "  -h, --help   Mostrar esta ayuda"
}

# Función para resetear configuración
reset_config() {
    warn "¿Estás seguro de que quieres resetear la configuración de Homer? [y/N]"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        log "Reseteando configuración..."
        if [ -f "configs/homer/config.yml.backup" ]; then
            cp configs/homer/config.yml.backup configs/homer/config.yml
        fi
        configure_homer
    else
        info "Operación cancelada"
    fi
}

# Función para editar configuración
edit_config() {
    info "Editando configuración de Homer..."
    ${EDITOR:-nano} configs/homer/config.yml
    
    warn "¿Reiniciar Homer para aplicar cambios? [y/N]"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        docker compose restart homer
        log "Homer reiniciado"
    fi
}

# Parsear argumentos
case "${1:-configure}" in
    configure)
        configure_homer
        show_services
        ;;
    reset)
        reset_config
        ;;
    show)
        show_services
        ;;
    edit)
        edit_config
        ;;
    -h|--help)
        show_help
        ;;
    *)
        error "Opción desconocida: $1. Usa -h para ver la ayuda."
        ;;
esac
