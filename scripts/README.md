# Scripts de Despliegue Homelab

Esta carpeta contiene scripts para automatizar el despliegue y gestión del homelab en sistemas Linux desde cero.

## Scripts Disponibles

### 1. `deploy-homelab.sh` - Script Principal de Despliegue
Instala y configura todo el homelab desde una máquina Linux limpia.

**Características:**
- Detecta distribución (Ubuntu/Debian/CentOS/RHEL/Fedora)
- Instala Docker y dependencias
- Configura sistema (usuarios, límites, firewall)
- Clona repositorio y configura variables
- Despliega servicios según escenario

**Uso:**
```bash
# Descarga y ejecución directa
curl -fsSL https://raw.githubusercontent.com/andonisan/nas/main/scripts/deploy-homelab.sh | bash

# O descarga local
wget https://raw.githubusercontent.com/andonisan/nas/main/scripts/deploy-homelab.sh
chmod +x deploy-homelab.sh
./deploy-homelab.sh --scenario=B --domain=home.arpa
```

**Parámetros:**
- `--scenario=A|B|C`: Escenario a desplegar (por defecto: B)
- `--domain=ejemplo.com`: Dominio base (por defecto: home.arpa)  
- `--install-path=/ruta`: Ruta de instalación (por defecto: /srv/homelab)

**Escenarios:**
- **A**: Básico (Caddy + Homer + Jellyfin + Syncthing)
- **B**: Fotos + Monitoreo (A + Immich + Netdata + Uptime Kuma)
- **C**: Completo (B + AdGuard + File Browser)

### 2. `manage-homelab.sh` - Gestión Post-Despliegue
Script para administrar el homelab una vez desplegado.

**Comandos:**
```bash
./manage-homelab.sh status          # Estado de servicios
./manage-homelab.sh logs [servicio] # Ver logs
./manage-homelab.sh restart         # Reiniciar servicios
./manage-homelab.sh update          # Actualizar imágenes
./manage-homelab.sh backup          # Crear backup completo
./manage-homelab.sh restore FECHA   # Restaurar backup
./manage-homelab.sh add-profile     # Añadir servicios
./manage-homelab.sh remove-profile  # Quitar servicios
./manage-homelab.sh monitor         # Monitor en tiempo real
./manage-homelab.sh cleanup         # Limpiar sistema
./manage-homelab.sh config          # Ver configuración
./manage-homelab.sh ssl             # Configurar SSL local
```

### 3. `quick-install.sh` - Instalación One-Liner
Script minimalista para instalación rápida.

**Uso:**
```bash
# Instalación con parámetros por defecto (Escenario B)
curl -fsSL https://raw.githubusercontent.com/andonisan/nas/main/scripts/quick-install.sh | bash

# Con parámetros personalizados
curl -fsSL https://raw.githubusercontent.com/andonisan/nas/main/scripts/quick-install.sh | bash -s -- --scenario=C --domain=mi.local
```

## Requisitos del Sistema

**Mínimos:**
- Linux (Ubuntu 20.04+, Debian 11+, CentOS 8+)
- 4GB RAM
- 20GB espacio libre
- Usuario con sudo (NO ejecutar como root)

**Recomendados (Escenario B):**
- 8-12GB RAM
- 50GB+ espacio libre
- SSD para mejor rendimiento

## Estructura Post-Instalación

```
/srv/homelab/           # Código del homelab
├── compose.yaml        # Configuración Docker Compose
├── .env               # Variables de entorno
├── secrets/           # Secretos (no versionados)
└── scripts/           # Scripts de gestión

/srv/data/             # Datos de aplicaciones
├── shared/            # Archivos Syncthing
├── media/             # Media Jellyfin
│   ├── movies/
│   └── series/
└── photos/            # Fotos Immich
    └── library/

/srv/backups/          # Backups automáticos
├── postgres/          # Dumps PostgreSQL
└── restic/           # Backups offsite (opcional)
```

## Configuración de Red

Los scripts configuran automáticamente:

1. **Firewall básico** (UFW/firewalld):
   - Puerto 22 (SSH)
   - Puerto 80/443 (HTTP/HTTPS)
   - Puerto 53 (DNS) solo desde redes locales

2. **DNS local** (/etc/hosts):
   - dashboard.home.arpa → 127.0.0.1
   - jellyfin.home.arpa → 127.0.0.1
   - fotos.home.arpa → 127.0.0.1
   - etc.

3. **Servicios expuestos**:
   - Caddy reverse proxy (80/443)
   - AdGuard DNS (53) - solo localhost por defecto

## Personalización

### Variables de Entorno (.env)
Principales variables a personalizar:

```bash
# Dominio base
HEIMDALL_DOMAIN=dashboard.tudominio.com  # Homer dashboard
JELLYFIN_DOMAIN=jellyfin.tudominio.com

# Rutas de datos
MEDIA_MOVIES_PATH=/ruta/a/peliculas
MEDIA_SERIES_PATH=/ruta/a/series
SYNC_DATA_PATH=/ruta/a/sincronizacion

# Configuración usuario
PUID=1000
PGID=1000
TZ=Europe/Madrid

# Networking
ADGUARD_BIND_IP=0.0.0.0  # Para exponer DNS externamente
```

### Perfiles Docker Compose
Activar/desactivar servicios:

```bash
# Ver servicios activos
docker compose ps

# Añadir servicio
docker compose --profile monitoring up -d

# Quitar servicio
docker compose stop netdata uptime-kuma
```

## Backups

### Automáticos
- PostgreSQL: dumps diarios a las 3:00 AM
- Retención: 7 días automáticamente

### Manuales
```bash
# Backup completo
./scripts/manage-homelab.sh backup

# Backup con nombre personalizado
./scripts/manage-homelab.sh backup mi-backup-importante

# Restaurar
./scripts/manage-homelab.sh restore 2024-01-15
```

## Troubleshooting

### Problemas Comunes

1. **Docker sin permisos**:
   ```bash
   sudo usermod -aG docker $USER
   newgrp docker
   ```

2. **Servicios no accesibles**:
   - Verificar firewall: `sudo ufw status`
   - Verificar DNS: `nslookup dashboard.home.arpa`
   - Verificar logs: `./scripts/manage-homelab.sh logs caddy`

3. **Poco espacio en disco**:
   ```bash
   ./scripts/manage-homelab.sh cleanup
   docker system prune -a
   ```

4. **Performance issues**:
   ```bash
   ./scripts/manage-homelab.sh monitor
   # Verificar uso de CPU/RAM por contenedor
   ```

### Logs Importantes
```bash
# Logs del sistema
journalctl -u docker
systemctl status docker

# Logs de servicios
docker compose logs -f caddy
docker compose logs -f postgres

# Monitor en tiempo real
./scripts/manage-homelab.sh monitor
```

## Actualizaciones

### Automáticas (Watchtower)
Si está habilitado el perfil `watchtower`:
- Actualización diaria a las 4:00 AM
- Solo imágenes con tag `:latest`

### Manuales
```bash
# Actualizar imágenes y servicios
./scripts/manage-homelab.sh update

# Actualizar solo código
cd /srv/homelab
git pull origin main
docker compose up -d
```

## Seguridad

### Implementado por Scripts
- Firewall básico configurado
- PostgreSQL con contraseña en secreto
- AdGuard DNS solo localhost por defecto
- Logs rotativos (SystemD)
- Usuarios no-root para contenedores

### Recomendaciones Adicionales
- Cambiar puertos SSH por defecto
- Configurar fail2ban
- Usar certificados SSL válidos para acceso externo
- VPN para acceso remoto seguro
- Backups offsite automáticos

## Soporte

Para problemas o mejoras, crear issue en:
https://github.com/andonisan/nas/issues
