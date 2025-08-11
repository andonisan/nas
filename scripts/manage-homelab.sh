#!/bin/bash
set -euo pipefail

# Homelab Management Script
# Gestión y mantenimiento del homelab desplegado

INSTALL_PATH="/srv/homelab"
BACKUP_PATH="/srv/backups"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[INFO] $1${NC}"; }

cd "$INSTALL_PATH" || error "No se encuentra $INSTALL_PATH"

show_help() {
    echo "Homelab Management Script"
    echo
    echo "Uso: $0 <comando> [opciones]"
    echo
    echo "Comandos disponibles:"
    echo "  status          - Mostrar estado de servicios"
    echo "  logs [servicio] - Ver logs (todos o servicio específico)"
    echo "  restart         - Reiniciar todos los servicios"
    echo "  update          - Actualizar imágenes y reiniciar"
    echo "  backup          - Crear backup completo"
    echo "  restore [fecha] - Restaurar backup (formato: YYYY-MM-DD)"
    echo "  add-profile     - Añadir perfil de servicios"
    echo "  remove-profile  - Quitar perfil de servicios"
    echo "  monitor         - Mostrar uso de recursos"
    echo "  cleanup         - Limpiar imágenes y volúmenes no usados"
    echo "  config          - Mostrar configuración actual"
    echo "  configure-heimdall - Configurar dashboard de Homer"
    echo "  ssl             - Configurar certificados SSL locales"
    echo "  help            - Mostrar esta ayuda"
}

show_status() {
    log "Estado de servicios del homelab:"
    echo
    docker compose ps
    echo
    info "Uso de recursos:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
}

show_logs() {
    local service="${1:-}"
    if [[ -n "$service" ]]; then
        log "Logs de $service:"
        docker compose logs -f --tail=100 "$service"
    else
        log "Logs de todos los servicios:"
        docker compose logs -f --tail=50
    fi
}

restart_services() {
    log "Reiniciando servicios..."
    docker compose restart
    log "Servicios reiniciados"
}

update_services() {
    log "Actualizando servicios..."
    
    # Backup antes de actualizar
    create_backup "pre-update-$(date +%Y%m%d-%H%M%S)"
    
    # Actualizar imágenes
    docker compose pull
    
    # Reiniciar servicios
    docker compose up -d --remove-orphans
    
    # Limpiar imágenes viejas
    docker image prune -f
    
    log "Servicios actualizados"
}

create_backup() {
    local backup_name="${1:-homelab-$(date +%Y%m%d-%H%M%S)}"
    local backup_dir="$BACKUP_PATH/$backup_name"
    
    log "Creando backup: $backup_name"
    
    mkdir -p "$backup_dir"
    
    # Backup de configuración
    tar -czf "$backup_dir/config.tar.gz" -C "$INSTALL_PATH" .env secrets/ || warn "Error en backup de config"
    
    # Backup de volúmenes Docker
    log "Creando backup de volúmenes..."
    for volume in $(docker volume ls -q | grep "^$(basename $INSTALL_PATH)_"); do
        info "Backup volumen: $volume"
        docker run --rm -v "$volume":/data -v "$backup_dir":/backup ubuntu:20.04 \
            tar -czf "/backup/volume_${volume}.tar.gz" -C /data . || warn "Error en backup de $volume"
    done
    
    # Backup específico de PostgreSQL (si está corriendo)
    if docker compose ps postgres -q --status running &>/dev/null; then
        log "Backup de base de datos PostgreSQL..."
        docker compose exec -T postgres pg_dumpall -U postgres | gzip > "$backup_dir/postgres_full.sql.gz"
    fi
    
    # Metadatos del backup
    cat > "$backup_dir/metadata.txt" <<EOF
Backup: $backup_name
Fecha: $(date)
Host: $(hostname)
Usuario: $(whoami)
Docker Compose version: $(docker compose version --short)
Servicios activos: $(docker compose ps --services --filter "status=running" | tr '\n' ' ')
EOF
    
    log "Backup completado en: $backup_dir"
    
    # Mostrar tamaño
    du -sh "$backup_dir"
    
    # Limpiar backups antiguos (mantener 10)
    find "$BACKUP_PATH" -maxdepth 1 -type d -name "homelab-*" | sort | head -n -10 | xargs rm -rf 2>/dev/null || true
}

restore_backup() {
    local backup_date="${1:-}"
    if [[ -z "$backup_date" ]]; then
        error "Especificar fecha de backup (YYYY-MM-DD) o nombre completo"
    fi
    
    # Buscar backup
    local backup_dir
    if [[ -d "$BACKUP_PATH/$backup_date" ]]; then
        backup_dir="$BACKUP_PATH/$backup_date"
    else
        backup_dir=$(find "$BACKUP_PATH" -maxdepth 1 -type d -name "*$backup_date*" | head -1)
    fi
    
    if [[ -z "$backup_dir" || ! -d "$backup_dir" ]]; then
        error "Backup no encontrado para: $backup_date"
    fi
    
    warn "¡ATENCIÓN! Esto sobrescribirá la configuración actual."
    read -p "¿Continuar? (yes/NO): " confirm
    if [[ "$confirm" != "yes" ]]; then
        info "Operación cancelada"
        return
    fi
    
    log "Restaurando backup desde: $backup_dir"
    
    # Parar servicios
    docker compose down
    
    # Restaurar configuración
    if [[ -f "$backup_dir/config.tar.gz" ]]; then
        tar -xzf "$backup_dir/config.tar.gz" -C "$INSTALL_PATH"
    fi
    
    # Restaurar volúmenes
    for volume_backup in "$backup_dir"/volume_*.tar.gz; do
        if [[ -f "$volume_backup" ]]; then
            volume_name=$(basename "$volume_backup" .tar.gz | sed 's/volume_//')
            info "Restaurando volumen: $volume_name"
            docker volume create "$volume_name" || true
            docker run --rm -v "$volume_name":/data -v "$backup_dir":/backup ubuntu:20.04 \
                tar -xzf "/backup/$(basename "$volume_backup")" -C /data
        fi
    done
    
    # Restaurar PostgreSQL si existe backup
    if [[ -f "$backup_dir/postgres_full.sql.gz" ]]; then
        log "Iniciando PostgreSQL para restauración..."
        docker compose up -d postgres
        sleep 10
        
        log "Restaurando base de datos..."
        zcat "$backup_dir/postgres_full.sql.gz" | docker compose exec -T postgres psql -U postgres
    fi
    
    # Reiniciar servicios
    docker compose up -d
    
    log "Restauración completada"
}

add_profile() {
    local available_profiles=("photos" "network" "monitoring" "files" "watchtower")
    
    echo "Perfiles disponibles:"
    for i in "${!available_profiles[@]}"; do
        echo "  $((i+1)). ${available_profiles[$i]}"
    done
    
    read -p "Seleccionar número de perfil: " selection
    if [[ "$selection" =~ ^[1-9]$ && "$selection" -le "${#available_profiles[@]}" ]]; then
        local profile="${available_profiles[$((selection-1))]}"
        log "Añadiendo perfil: $profile"
        docker compose --profile "$profile" up -d
    else
        error "Selección inválida"
    fi
}

remove_profile() {
    local running_profiles
    mapfile -t running_profiles < <(docker compose ps --services --filter "status=running")
    
    if [[ ${#running_profiles[@]} -eq 0 ]]; then
        info "No hay servicios en ejecución"
        return
    fi
    
    echo "Servicios en ejecución:"
    for i in "${!running_profiles[@]}"; do
        echo "  $((i+1)). ${running_profiles[$i]}"
    done
    
    read -p "Seleccionar servicio a parar (número): " selection
    if [[ "$selection" =~ ^[1-9]$ && "$selection" -le "${#running_profiles[@]}" ]]; then
        local service="${running_profiles[$((selection-1))]}"
        log "Parando servicio: $service"
        docker compose stop "$service"
    else
        error "Selección inválida"
    fi
}

monitor_resources() {
    log "Monitoreo de recursos (Ctrl+C para salir):"
    echo
    while true; do
        clear
        echo "=== HOMELAB MONITORING ==="
        echo "Tiempo: $(date)"
        echo
        
        # CPU y memoria del sistema
        echo "=== SISTEMA ==="
        echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4"%"}')"
        echo "RAM: $(free -h | awk '/^Mem:/ {printf "%s/%s (%.1f%%)", $3, $2, ($3/$2)*100}')"
        echo "Disco: $(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3, $2, $5}')"
        echo
        
        # Contenedores
        echo "=== CONTENEDORES ==="
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | head -10
        echo
        
        sleep 5
    done
}

cleanup_system() {
    log "Limpiando sistema..."
    
    # Limpiar imágenes no usadas
    docker image prune -f
    
    # Limpiar volúmenes no usados
    docker volume prune -f
    
    # Limpiar redes no usadas
    docker network prune -f
    
    # Limpiar contenedores parados
    docker container prune -f
    
    # Estadísticas
    echo
    info "Espacio liberado:"
    docker system df
    
    log "Limpieza completada"
}

show_config() {
    log "Configuración actual del homelab:"
    echo
    
    echo "=== ARCHIVOS DE CONFIGURACIÓN ==="
    echo "Ubicación: $INSTALL_PATH"
    echo "Variables de entorno (.env):"
    grep -E "^[A-Z]" "$INSTALL_PATH/.env" | head -10
    echo
    
    echo "=== SERVICIOS CONFIGURADOS ==="
    docker compose config --services
    echo
    
    echo "=== VOLÚMENES ==="
    docker volume ls | grep "^$(basename $INSTALL_PATH)_"
    echo
    
    echo "=== REDES ==="
    docker network ls | grep "$(basename $INSTALL_PATH)"
}

setup_ssl() {
    log "Configurando certificados SSL locales con mkcert..."
    
    # Instalar mkcert si no existe
    if ! command -v mkcert &> /dev/null; then
        info "Instalando mkcert..."
        curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
        chmod +x mkcert-v*-linux-amd64
        sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert
    fi
    
    # Crear CA local
    mkcert -install
    
    # Crear certificados para dominios del homelab
    local domain=$(grep HEIMDALL_DOMAIN .env | cut -d= -f2 | sed 's/dashboard\.//')
    
    mkdir -p ssl
    cd ssl
    
    mkcert \
        "dashboard.$domain" \
        "jellyfin.$domain" \
        "fotos.$domain" \
        "adguard.$domain" \
        "metrics.$domain" \
        "status.$domain" \
        "files.$domain" \
        "*.$domain"
    
    cd ..
    
    info "Certificados SSL creados en ./ssl/"
    warn "Configurar Caddy para usar estos certificados"
}

# Función principal
main() {
    case "${1:-help}" in
        status)
            show_status
            ;;
        logs)
            show_logs "${2:-}"
            ;;
        restart)
            restart_services
            ;;
        update)
            update_services
            ;;
        backup)
            create_backup "${2:-}"
            ;;
        restore)
            restore_backup "${2:-}"
            ;;
        add-profile)
            add_profile
            ;;
        remove-profile)
            remove_profile
            ;;
        monitor)
            monitor_resources
            ;;
        cleanup)
            cleanup_system
            ;;
        config)
            show_config
            ;;
        configure-heimdall)
            if [[ -f "scripts/configure-homer.sh" ]]; then
                chmod +x scripts/configure-homer.sh
                scripts/configure-homer.sh "${2:-configure}"
            else
                error "Script configure-homer.sh no encontrado"
            fi
            ;;
        ssl)
            setup_ssl
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Comando no reconocido: ${1:-}. Usar 'help' para ver comandos disponibles."
            ;;
    esac
}

# Verificar que estamos en el directorio correcto
if [[ ! -f "compose.yaml" ]]; then
    error "No se encuentra compose.yaml. Ejecutar desde $INSTALL_PATH"
fi

main "$@"
