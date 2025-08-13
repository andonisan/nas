#!/bin/bash
set -euo pipefail

# Homelab Deploy Script - Sistema Linux desde cero
# Compatible con: Ubuntu 20.04+, Debian 11+, CentOS/RHEL 8+
# Uso: curl -fsSL https://raw.githubusercontent.com/andonisan/nas/main/scripts/deploy-homelab.sh | bash
# O: ./scripts/deploy-homelab.sh [--scenario=B] [--domain=home.arpa] [--install-path=/srv/homelab]

# Configuración por defecto
SCENARIO="${1:-C}"
DOMAIN="${2:-home.arpa}"
INSTALL_PATH="${3:-/srv/homelab}"
COMPOSE_PROJECT_NAME="homelab"
USER_UID=$(id -u)
USER_GID=$(id -g)

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Detectar distribución
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        error "No se puede detectar la distribución del sistema"
    fi
    
    log "Detectado: $OS $VER"
}

# Verificar requisitos mínimos
check_requirements() {
    log "Verificando requisitos del sistema..."
    
    # RAM mínima 4GB
    RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $RAM_GB -lt 4 ]]; then
        error "RAM insuficiente: ${RAM_GB}GB (mínimo 4GB)"
    fi
    
    # Espacio en disco mínimo 20GB
    DISK_GB=$(df / | awk 'NR==2{printf "%.0f", $4/1024/1024}')
    if [[ $DISK_GB -lt 18 ]]; then
        error "Espacio en disco insuficiente: ${DISK_GB}GB (mínimo 20GB)"
    fi
    
    info "Requisitos OK: ${RAM_GB}GB RAM, ${DISK_GB}GB disco disponible"
}

# Actualizar sistema
update_system() {
    log "Actualizando sistema..."
    case $OS in
        ubuntu|debian)
            sudo apt update && sudo apt upgrade -y
            sudo apt install -y curl wget git unzip htop nano
            ;;
        centos|rhel|fedora)
            sudo dnf update -y
            sudo dnf install -y curl wget git unzip htop nano
            ;;
        *)
            warn "Distribución no soportada completamente: $OS"
            ;;
    esac
}

# Instalar Docker
install_docker() {
    if command -v docker &> /dev/null; then
        log "Docker ya está instalado: $(docker --version)"
        return
    fi
    
    log "Instalando Docker..."
    case $OS in
        ubuntu|debian)
            # Método oficial Docker
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh
            rm get-docker.sh
            ;;
        centos|rhel|fedora)
            sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
    esac
    
    # Configurar Docker
    sudo systemctl enable docker
    sudo systemctl start docker
    
    # Añadir usuario actual al grupo docker
    sudo usermod -aG docker $USER
    
    log "Docker instalado correctamente"
}

# Configurar sistema para homelab
configure_system() {
    log "Configurando sistema para homelab..."
    
    # Crear usuario apps si no existe (con UID disponible)
    if ! id "apps" &>/dev/null; then
        # Buscar UID disponible si 1000 está ocupado
        if id -u 1000 &>/dev/null; then
            warn "UID 1000 ya existe, usando UID disponible automático"
            sudo useradd -s /bin/bash -m apps || true
        else
            sudo useradd -u 1000 -s /bin/bash -m apps || true
        fi
    fi
    
    # Configurar límites de archivo para contenedores
    sudo tee /etc/security/limits.d/docker.conf > /dev/null <<EOF
*               soft    nofile          65536
*               hard    nofile          65536
apps            soft    nofile          65536
apps            hard    nofile          65536
EOF
    
    # Configurar sysctl para contenedores
    sudo tee /etc/sysctl.d/99-homelab.conf > /dev/null <<EOF
# Configuración para homelab
vm.max_map_count=262144
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512
net.core.somaxconn=65535
# IP forwarding para Tailscale
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
    
    sudo sysctl -p /etc/sysctl.d/99-homelab.conf
    
    # Crear directorio para journald config si no existe
    sudo mkdir -p /etc/systemd/journald.conf.d
    
    # Configurar journald para evitar logs excesivos
    sudo tee /etc/systemd/journald.conf.d/homelab.conf > /dev/null <<EOF
[Journal]
SystemMaxUse=500M
RuntimeMaxUse=100M
MaxRetentionSec=7day
EOF
    
    sudo systemctl restart systemd-journald || warn "No se pudo reiniciar journald, continuando..."
    
    log "Sistema configurado correctamente"
}

# Validar configuración del sistema
validate_system() {
    log "Validando configuración del sistema..."
    
    # Verificar que los archivos de configuración se crearon
    if [[ ! -f /etc/sysctl.d/99-homelab.conf ]]; then
        error "No se pudo crear archivo sysctl"
    fi
    
    # Verificar que sysctl se aplicó
    if ! sysctl vm.max_map_count | grep -q 262144; then
        warn "vm.max_map_count no se aplicó correctamente"
    fi
    
    # Verificar usuario apps
    if id "apps" &>/dev/null; then
        info "Usuario apps creado: UID $(id -u apps)"
    else
        warn "Usuario apps no se pudo crear"
    fi
    
    info "Validación del sistema completada"
}

# Limpiar configuraciones anteriores si existen
cleanup_previous_config() {
    log "Limpiando configuraciones anteriores..."
    
    # Limpiar configuraciones systemd problemáticas
    if [[ -f /etc/systemd/journald.conf.d/homelab.conf ]]; then
        warn "Configuración journald anterior encontrada, limpiando..."
        sudo rm -f /etc/systemd/journald.conf.d/homelab.conf
    fi
    
    # Verificar conflictos de usuario
    if id -u 1000 &>/dev/null && [[ $(id -un 1000) != "apps" ]]; then
        warn "UID 1000 ocupado por usuario: $(id -un 1000)"
        info "Se usará UID automático para usuario apps"
    fi
    
    info "Limpieza completada"
}

# Instalar y configurar Tailscale
install_tailscale() {
    log "Instalando Tailscale..."
    
    if command -v tailscale &> /dev/null; then
        log "Tailscale ya está instalado: $(tailscale version)"
        return
    fi
    
    # Instalar Tailscale
    curl -fsSL https://tailscale.com/install.sh | sh
    
    # Habilitar servicio
    sudo systemctl enable tailscaled
    sudo systemctl start tailscaled
    
    log "Tailscale instalado correctamente"
    
    # Mostrar instrucciones para configuración
    info "Para configurar Tailscale:"
    echo "1. Obtén tu auth key en: https://login.tailscale.com/admin/settings/keys"
    echo "2. Añade TAILSCALE_AUTHKEY=tskey-auth-xxxxx a tu .env"
    echo "3. Ejecuta: docker compose --profile vpn up -d"
    echo "4. O usa el perfil network para incluir AdGuard: docker compose --profile network up -d"
    echo
}

# Configurar Tailscale auth (si existe el token)
configure_tailscale() {
    log "Configurando Tailscale..."
    
    # Verificar si existe auth key en .env
    if [[ -f .env ]] && grep -q "TAILSCALE_AUTHKEY=" .env; then
        TAILSCALE_AUTH=$(grep "TAILSCALE_AUTHKEY=" .env | cut -d'=' -f2)
        
        if [[ -n "$TAILSCALE_AUTH" && "$TAILSCALE_AUTH" != "tskey-auth-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" ]]; then
            info "Configurando Tailscale con auth key encontrado..."
            
            # Configurar Tailscale con subnet routing
            sudo tailscale up --authkey="$TAILSCALE_AUTH" \
                --advertise-routes=192.168.1.0/24,10.0.0.0/8 \
                --accept-routes \
                --hostname=homelab-$(hostname)
            
            log "Tailscale configurado correctamente"
            info "Recuerda aprobar las subnet routes en: https://login.tailscale.com/admin/machines"
        else
            warn "Auth key de Tailscale no configurado en .env"
            info "Configurar manualmente con: sudo tailscale up"
        fi
    else
        warn "No se encontró configuración de Tailscale en .env"
    fi
}

# Crear estructura de directorios
create_directories() {
    log "Creando estructura de directorios..."
    
    # Directorios principales
    sudo mkdir -p $INSTALL_PATH
    sudo mkdir -p /srv/data/{shared,media/{movies,series},photos/library}
    sudo mkdir -p /srv/backups/{postgres,restic}
    
    # Cambiar propietario
    sudo chown -R $USER:$USER $INSTALL_PATH
    sudo chown -R 1000:1000 /srv/data
    sudo chown -R $USER:$USER /srv/backups
    
    info "Directorios creados en $INSTALL_PATH y /srv/data"
}

# Clonar repositorio
clone_repository() {
    log "Clonando repositorio homelab..."
    
    if [[ -d "$INSTALL_PATH/.git" ]]; then
        cd $INSTALL_PATH
        git pull origin main
    else
        git clone https://github.com/andonisan/nas.git $INSTALL_PATH
        cd $INSTALL_PATH
    fi
}

# Configurar variables de entorno
configure_environment() {
    log "Configurando variables de entorno..."
    
    cp .env.example .env
    
    # Personalizar .env según parámetros
    sed -i "s/COMPOSE_PROJECT_NAME=homelab/COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME/" .env
    sed -i "s/home\.arpa/$DOMAIN/g" .env
    sed -i "s/PUID=1000/PUID=$USER_UID/" .env
    sed -i "s/PGID=1000/PGID=$USER_GID/" .env
    
    # Configurar rutas reales
    sed -i "s|/mnt/media/movies|/srv/data/media/movies|" .env
    sed -i "s|/mnt/media/series|/srv/data/media/series|" .env
    sed -i "s|/mnt/data/shared|/srv/data/shared|" .env
    sed -i "s|/mnt/photos/library|/srv/data/photos/library|" .env
    
    # Zona horaria del sistema
    TIMEZONE=$(timedatectl show --property=Timezone --value)
    sed -i "s|TZ=Europe/Madrid|TZ=$TIMEZONE|" .env
    
    info "Archivo .env configurado para $DOMAIN"
}

# Generar secretos
generate_secrets() {
    log "Generando secretos..."
    
    mkdir -p secrets
    
    # Contraseña PostgreSQL segura
    if [[ ! -f secrets/postgres_password.txt ]]; then
        openssl rand -base64 32 > secrets/postgres_password.txt
        chmod 600 secrets/postgres_password.txt
    fi
    
    info "Secretos generados en ./secrets/"
}

# Configurar firewall básico
configure_firewall() {
    log "Configurando firewall básico..."
    
    if command -v ufw &> /dev/null; then
        sudo ufw --force enable
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        sudo ufw allow ssh
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        # AdGuard DNS solo desde red local (ajustar según red)
        sudo ufw allow from 192.168.0.0/16 to any port 53
        sudo ufw allow from 10.0.0.0/8 to any port 53
        info "Firewall UFW configurado"
    elif command -v firewall-cmd &> /dev/null; then
        sudo systemctl enable firewalld
        sudo systemctl start firewalld
        sudo firewall-cmd --permanent --add-service=ssh
        sudo firewall-cmd --permanent --add-service=http
        sudo firewall-cmd --permanent --add-service=https
        sudo firewall-cmd --permanent --add-service=dns
        sudo firewall-cmd --reload
        info "Firewall firewalld configurado"
    else
        warn "No se encontró UFW ni firewalld. Configurar firewall manualmente."
    fi
}

# Configurar Homer automáticamente
configure_homer() {
    log "Configurando Homer dashboard..."
    
    # Crear copia del config y configurar dominio
    cp configs/homer/config.yml configs/homer/config.yml.tmp
    chmod +x configs/homer/configure.sh
    configs/homer/configure.sh configs/homer/config.yml.tmp "$DOMAIN"
    
    # Reemplazar config original
    mv configs/homer/config.yml.tmp configs/homer/config.yml
    
    log "Homer configurado automáticamente para dominio: $DOMAIN"
}

# Desplegar servicios según escenario
deploy_services() {
    log "Desplegando servicios (Escenario $SCENARIO)..."
    
    # Verificar que Docker funciona sin sudo
    if ! docker ps &>/dev/null; then
        warn "Reiniciando sesión para aplicar grupo docker..."
        echo "Ejecuta: newgrp docker"
        echo "Luego continúa con: docker compose --profile photos up -d"
        return
    fi
    
    # Descargar imágenes
    docker compose pull
    
    case $SCENARIO in
        A)
            info "Desplegando Escenario A: Básico (media + archivos)"
            docker compose up -d
            ;;
        B)
            info "Desplegando Escenario B: Fotos + Monitoreo"
            docker compose --profile photos --profile monitoring up -d
            ;;
        C)
            info "Desplegando Escenario C: Completo Básico (B + Red + Archivos)"
            docker compose --profile photos --profile monitoring --profile network --profile files up -d
            ;;
        D)
            info "Desplegando Escenario D: Homelab Avanzado (C + Seguridad + Gestión + Backups)"
            docker compose --profile photos --profile monitoring --profile network --profile files --profile security --profile management --profile backup up -d
            ;;
        *)
            error "Escenario no válido: $SCENARIO (usar A, B, C o D)"
            ;;
    esac
    
    log "Servicios desplegados correctamente"
}

# Configurar DNS local básico
configure_dns() {
    log "Configurando resolución DNS local..."
    
    # Backup del hosts original
    sudo cp /etc/hosts /etc/hosts.backup
    
    # Añadir entradas para el homelab
    sudo tee -a /etc/hosts > /dev/null <<EOF

# Homelab services
127.0.0.1 dashboard.$DOMAIN
127.0.0.1 jellyfin.$DOMAIN
127.0.0.1 fotos.$DOMAIN
127.0.0.1 adguard.$DOMAIN
127.0.0.1 metrics.$DOMAIN
127.0.0.1 status.$DOMAIN
127.0.0.1 files.$DOMAIN
127.0.0.1 sync.dashboard.$DOMAIN
127.0.0.1 vault.$DOMAIN
127.0.0.1 docker.$DOMAIN
127.0.0.1 backup.$DOMAIN
127.0.0.1 grafana.$DOMAIN
EOF
    
    info "DNS local configurado en /etc/hosts"
}

# Mostrar resumen final
show_summary() {
    log "¡Despliegue completado!"
    
    echo
    info "=== RESUMEN DEL HOMELAB ==="
    echo "Escenario: $SCENARIO"
    echo "Dominio: $DOMAIN"
    echo "Ruta: $INSTALL_PATH"
    echo "Proyecto: $COMPOSE_PROJECT_NAME"
    echo
    
    info "=== SERVICIOS DISPONIBLES ==="
    echo "🏠 Dashboard: http://dashboard.$DOMAIN"
    echo "🎬 Jellyfin: http://jellyfin.$DOMAIN"
    
    if [[ $SCENARIO == "B" || $SCENARIO == "C" ]]; then
        echo "📸 Immich (Fotos): http://fotos.$DOMAIN"
        echo "📊 Netdata: http://metrics.$DOMAIN"
        echo "⏰ Uptime Kuma: http://status.$DOMAIN"
    fi
    
    if [[ $SCENARIO == "C" || $SCENARIO == "D" ]]; then
        echo "🛡️  AdGuard: http://adguard.$DOMAIN"
        echo "📁 File Browser: http://files.$DOMAIN"
    fi
    
    if [[ $SCENARIO == "D" ]]; then
        echo "🔐 Vaultwarden: http://vault.$DOMAIN"
        echo "🐳 Portainer: http://docker.$DOMAIN" 
        echo "💾 Duplicati: http://backup.$DOMAIN"
    fi
    
    echo "🔄 Syncthing: http://sync.dashboard.$DOMAIN"
    echo
    
    info "=== COMANDOS ÚTILES ==="
    echo "Ver estado: docker compose ps"
    echo "Ver logs: docker compose logs -f"
    echo "Reiniciar: docker compose restart"
    echo "Actualizar: docker compose pull && docker compose up -d"
    echo "Parar: docker compose down"
    echo
    
    info "=== ARCHIVOS IMPORTANTES ==="
    echo "Configuración: $INSTALL_PATH/.env"
    echo "Secretos: $INSTALL_PATH/secrets/"
    echo "Datos: /srv/data/"
    echo "Backups: /srv/backups/"
    echo
    
    warn "NOTAS IMPORTANTES:"
    echo "- Configurar DNS en router o usar /etc/hosts en otros dispositivos"
    echo "- Backups automáticos de PostgreSQL en /srv/backups/postgres/"
    echo "- Para acceso externo, configurar port forwarding en router"
    echo "- Revisar configuración de AdGuard en primer acceso"
    echo "- Tailscale instalado - configurar auth key en .env para VPN automático"
    echo "- Para acceso remoto via Tailscale: usar IP 100.x.x.x del dispositivo"
}

# Función principal
main() {
    log "Iniciando despliegue de homelab..."
    
    # Parsear argumentos
    for arg in "$@"; do
        case $arg in
            --scenario=*)
                SCENARIO="${arg#*=}"
                ;;
            --domain=*)
                DOMAIN="${arg#*=}"
                ;;
            --install-path=*)
                INSTALL_PATH="${arg#*=}"
                ;;
            -h|--help)
                echo "Uso: $0 [--scenario=A|B|C|D] [--domain=home.arpa] [--install-path=/srv/homelab]"
                echo
                echo "Escenarios:"
                echo "  A: Básico (media + sync + dashboard)"
                echo "  B: Fotos + Monitoreo (A + Immich + Netdata + Uptime Kuma)"
                echo "  C: Completo Básico (B + AdGuard + File Browser + Tailscale)"
                echo "  D: Homelab Avanzado (C + Vaultwarden + Portainer + Duplicati)"
                exit 0
                ;;
        esac
    done
    
    # Verificar si se ejecuta como root
    if [[ $EUID -eq 0 ]]; then
        error "No ejecutar como root. Usar usuario normal con sudo."
    fi
    
    # Verificar sudo
    if ! sudo -n true 2>/dev/null; then
        info "Se requieren permisos de administrador."
        sudo -v
    fi
    
    # Ejecutar pasos
    detect_os
    check_requirements
    update_system
    install_docker
    install_tailscale
    cleanup_previous_config
    configure_system
    validate_system
    create_directories
    clone_repository
    configure_environment
    generate_secrets
    configure_tailscale
    configure_firewall
    configure_dns
    configure_homer
    deploy_services
    show_summary
    
    log "¡Homelab desplegado exitosamente!"
}

# Ejecutar si se llama directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
