# Homelab (GitOps-lite)

Stack Docker reproducible (multimedia, sincronización y fotos opcional) con mínimo scripting. Despliegue automatizado vía GitHub Actions por SSH. Reverse proxy automático con Caddy Docker Proxy (labels).

## Componentes
- Caddy (lucaslorentz/caddy-docker-proxy) – reverse proxy autodiscovery
- Homer – dashboard ultra-ligero con todos los servicios preconfigurados
- Jellyfin – media server (aceleración HW opcional /dev/dri)
- Syncthing – sincronización
- (Perfil photos) Postgres + Redis + Immich + backups programados
- (Perfil network) AdGuard Home – bloqueo DNS/anuncios
- (Perfil network/vpn) Tailscale – VPN mesh para acceso remoto
- (Perfil monitoring) Netdata + Uptime Kuma – métricas y uptime
- (Perfil monitoring-advanced) Grafana + InfluxDB – dashboards avanzados
- (Perfil files) File Browser – explorador web ligero
- (Perfil security) Vaultwarden – gestor de contraseñas Bitwarden
- (Perfil management) Portainer – gestión visual de Docker
- (Perfil backup) Duplicati – backups automáticos a la nube
- (Perfil watchtower) Watchtower (actualización automática de imágenes)

## Requisitos Host
- Docker Engine + plugin compose
- Ruta clonada: /srv/homelab
- Archivo secrets/postgres_password.txt (si usas perfil photos)
- DNS o resoluciones locales para los dominios (*.home.arpa)

## Inicio Rápido

### Opción A: Instalación Automática (Linux)
Para máquinas Linux desde cero:

```bash
# Instalación one-liner (Escenario B por defecto)
curl -fsSL https://raw.githubusercontent.com/andonisan/nas/main/scripts/quick-install.sh | bash

# Con parámetros personalizados
curl -fsSL https://raw.githubusercontent.com/andonisan/nas/main/scripts/quick-install.sh | bash -s -- --scenario=C --domain=mi.local
```

### Opción B: Instalación Manual
```bash
git clone <repo> /srv/homelab
cd /srv/homelab
cp .env.example .env
mkdir -p secrets
echo "contraseña-super-segura" > secrets/postgres_password.txt
docker compose up -d
# Añadir Immich y DB
docker compose --profile photos up -d
# (Opcional) añadir watchtower
docker compose --profile watchtower up -d
```

Accede:
- https://dashboard.home.arpa (Homer Dashboard)
- https://jellyfin.home.arpa (Jellyfin)
- https://fotos.home.arpa (Immich - si perfil photos)
- https://adguard.home.arpa (AdGuard - si perfil network)
- https://metrics.home.arpa (Netdata - si perfil monitoring)
- https://status.home.arpa (Uptime Kuma - si perfil monitoring)
- https://files.home.arpa (File Browser - si perfil files)

## Perfiles
| Perfil | Servicios |
|--------|-----------|
| (base) | caddy, homer, jellyfin, syncthing |
| photos | postgres, redis, immich-server, immich-machine-learning, pgbackups |
| network | adguardhome, tailscale |
| vpn | tailscale |
| monitoring | netdata, uptime-kuma |
| monitoring-advanced | influxdb, grafana |
| files | filebrowser |
| security | vaultwarden |
| management | portainer |
| backup | duplicati |
| watchtower | watchtower |

Ejemplos:
- Escenario A (básico): `docker compose up -d`
- Escenario B (fotos + monitoreo): `docker compose --profile photos --profile monitoring up -d`
- Escenario C (completo básico): `docker compose --profile photos --profile monitoring --profile network --profile files up -d`
- Escenario D (homelab avanzado): `docker compose --profile photos --profile monitoring --profile network --profile security --profile management --profile backup up -d`

## GitOps / Deploy Automático
1. Configura GitHub Secrets en el repo:
   - HOST: IP o FQDN del host
   - SSH_USER: usuario con acceso a /srv/homelab
   - SSH_KEY: clave privada (ed25519), sin passphrase (o usa agente)
2. Cada push a main dispara deploy.yml:
   - Hace git reset --hard origin/main
   - docker compose pull
   - docker compose up -d --remove-orphans
   - Limpia imágenes antiguas.
Rollback: `git revert <commit>` → push → acción redeploy.

## Estructura
```
compose.yaml
.env.example
.github/workflows/
  ├─ compose-validate.yml
  └─ deploy.yml
README.md
docs/ARCHITECTURE.md
secrets/ (no versionado)
```

## Backups Postgres
Servicio pgbackups (cron configurable PG_BACKUP_CRON, por defecto 03:00) genera dumps en volumen pg_dumps con rotación (KEEP_DAYS=7).

Restaurar (ejemplo):
```bash
# Localiza el dump (dentro del volumen). Luego:
gunzip -c /var/lib/docker/volumes/${COMPOSE_PROJECT_NAME}_pg_dumps/_data/immich_YYYY-MM-DD.sql.gz \
  | docker compose exec -T postgres psql -U $PG_USER -d $PG_DB
```
Recomendado: sincronizar ese volumen offsite (restic / rclone) añadiendo otro contenedor especializado si lo necesitas.

## Escenario B - Beelink (12GB RAM, CPU N150)
Configuración optimizada para mini-PC con recursos limitados:

**Tuning aplicado:**
- PostgreSQL: shared_buffers=128MB, work_mem=4MB, max_connections=30
- Immich: IMAGES_WORKERS=1, VIDEOS_WORKERS=1, ML desactivado por defecto
- AdGuard: bind solo a localhost (no expone DNS externamente)
- Netdata: modo local con PID host para monitoreo completo

**Consumo estimado idle:** ~1.2-1.6 GB sin Immich; ~2.0-2.4 GB con Immich

**Comandos específicos:**
```bash
# Stack básico + fotos
docker compose --profile photos up -d

# Añadir monitoreo ligero
docker compose --profile photos --profile monitoring up -d

# Stack completo Escenario B
docker compose --profile photos --profile monitoring --profile network --profile files up -d
```

## Aceleración Jellyfin
- Asegura presencia de /dev/dri (en Proxmox LXC: permitir dispositivo y montar).
- Si no necesitas HW transcode, puedes quitar la sección devices.

## Configuración Tailscale
Tailscale se instala automáticamente durante el deploy y proporciona acceso remoto seguro:

### Configuración Automática
El script de deploy instala Tailscale automáticamente. Para configurarlo:

1. Obtén auth key en [Tailscale Admin](https://login.tailscale.com/admin/settings/keys)
2. Añade a tu `.env` antes del deploy:
```bash
TAILSCALE_AUTHKEY=tskey-auth-xxxxxx
TAILSCALE_ROUTES=192.168.1.0/24  # Tu subnet local
```
3. El deploy configurará automáticamente subnet routing

### Configuración Manual (Post-Deploy)
Si no configuraste el auth key durante el deploy:
```bash
# Configurar Tailscale manualmente
sudo tailscale up --advertise-routes=192.168.1.0/24 --accept-routes

# O usar el contenedor Docker
docker compose --profile vpn up -d
```

### Modos de Operación
```bash
# Solo cliente VPN (contenedor)
docker compose --profile vpn up -d

# Con subnet routing + AdGuard (completo)
docker compose --profile network up -d
```

### Acceso Remoto
Una vez configurado:
- Aprobar subnet routes en [Tailscale Admin Console](https://login.tailscale.com/admin/machines)
- Acceder desde cualquier lugar: `http://100.x.x.x` (IP Tailscale del homelab)
- Opcional: configurar MagicDNS para nombres amigables

## Servicios Adicionales

### Vaultwarden (Gestor de Contraseñas)
Servidor Bitwarden auto-hospedado, compatible con todas las apps oficiales:

```bash
# Generar admin token
openssl rand -base64 48

# Añadir a .env
VAULTWARDEN_ADMIN_TOKEN=token_generado

# Desplegar
docker compose --profile security up -d
```

**Acceso**: https://vault.home.arpa
- **Primera configuración**: Crear cuenta admin
- **Panel admin**: https://vault.home.arpa/admin (usar ADMIN_TOKEN)

### Portainer (Gestión Docker)
Interfaz web para gestionar contenedores, imágenes, volúmenes:

```bash
docker compose --profile management up -d
```

**Acceso**: https://docker.home.arpa
- **Primera configuración**: Crear usuario admin
- **Funciones**: Ver logs, reiniciar servicios, gestionar volúmenes

### Duplicati (Backups Automáticos)
Backups cifrados hacia Google Drive, Dropbox, S3, etc:

```bash
# Configurar rutas en .env
BACKUP_SOURCE_PATH=/srv/data
DUPLICATI_BACKUP_PATH=/srv/backups/duplicati

docker compose --profile backup up -d
```

**Acceso**: https://backup.home.arpa
- **Configuración**: Crear trabajos de backup hacia la nube
- **Cifrado**: AES-256 con contraseña personalizada

### Grafana + InfluxDB (Monitoreo Avanzado)
Dashboards personalizables y almacenamiento de métricas a largo plazo:

```bash
docker compose --profile monitoring-advanced up -d
```

**Acceso**: https://grafana.home.arpa (admin/admin)
- **InfluxDB**: Base de datos interna para métricas
- **Dashboards**: Importar desde grafana.com o crear personalizados

## Dashboard Homer (Ultra-Ligero y Rápido)

**¿Por qué Homer en lugar de Heimdall?**
- 🚀 **Ultra-ligero**: Solo ~15MB RAM vs 150MB de Heimdall
- ⚡ **Velocidad**: Carga instantánea (sitio estático)
- 🔧 **DevOps-friendly**: Configuración YAML versionable
- 📱 **Responsivo**: Excelente en móviles
- 🎨 **Moderno**: Dark/light mode automático

### Configuración Automática
- **Durante deploy**: Se configura automáticamente con el dominio correcto
- **Configuración YAML**: Archivo simple y editable
- **Categorías organizadas**: Servicios agrupados lógicamente

### Gestión Manual
```bash
# Reconfigurar dashboard
./scripts/manage-homelab.sh configure-heimdall

# Editar configuración manualmente
./scripts/configure-homer.sh edit

# Ver servicios configurados
./scripts/configure-homer.sh show

# Resetear configuración
./scripts/configure-homer.sh reset
```

### Servicios Preconfigurados por Categorías

#### 📺 **Core Services**
- 🎬 **Jellyfin** - Servidor multimedia
- 🔄 **Syncthing** - Sincronización de archivos

#### 📸 **Photos & Media**
- 📸 **Immich** - Gestión de fotos (perfil photos)

#### 📊 **Monitoring**
- 📊 **Netdata** - Monitoreo en tiempo real (perfil monitoring)
- ⏰ **Uptime Kuma** - Monitor de disponibilidad (perfil monitoring)
- � **Grafana** - Dashboards avanzados (perfil monitoring-advanced)

#### 🛡️ **Network & Security**
- �️ **AdGuard Home** - Bloqueo DNS (perfil network)
- 🔐 **Vaultwarden** - Gestor de contraseñas (perfil security)

#### ⚙️ **Management & Files**
- 🐳 **Portainer** - Gestión Docker (perfil management)
- 📁 **File Browser** - Explorador web (perfil files)
- 💾 **Duplicati** - Backups automáticos (perfil backup)

### Ventajas de Homer vs Heimdall

| Aspecto | Homer | Heimdall |
|---------|-------|----------|
| **RAM** | ~15MB | ~150MB |
| **Velocidad** | Instantánea | Media |
| **Configuración** | YAML simple | SQLite complejo |
| **Mantenimiento** | Mínimo | Requiere gestión DB |
| **Responsivo** | Excelente | Bueno |
| **Temas** | Modernos | Básicos |

### Personalización
El archivo `configs/homer/config.yml` es completamente editable:
- Cambiar colores y temas
- Añadir/quitar servicios
- Reorganizar categorías
- Añadir enlaces externos

## Actualizaciones de Imágenes
Opciones:
1. Manual (recomendado para estabilidad): desactiva watchtower, usa PRs y versiones fijas (no latest).
2. Semi-automático: usar labels y una herramienta de notificación (Diun) (no incluida).
3. Automático: perfil watchtower (aplica nuevas versiones de madrugada).

Mitigación de riesgos watchtower: fijar tags a versiones concretas tras validar (ej. `lscr.io/linuxserver/jellyfin:10.9.9`).

## Seguridad
- Postgres y Redis sólo en red interna backend.
- Contraseña Postgres en secreto (secrets/postgres_password.txt) no en .env.
- Revisa que el host (o LXC) tenga firewall (ufw/nftables) si abres puertos fuera de la LAN.
- Certificados: Caddy puede emitir si usas dominios válidos; para LAN con TLD no público (home.arpa) usará auto-cert interno o HTTP interno sin TLS válido (considera mkcert si deseas confianza local).

## Migración a Proxmox (LXC)
1. Crear LXC Debian con nesting=1.
2. Bind mounts a rutas de datos (/mnt/media, etc.).
3. Instalar Docker.
4. Clonar repo y reproducir pasos de Inicio.
5. Passthrough GPU: añadir en config LXC:
```
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
```

## Gestión Post-Despliegue

Una vez desplegado, usar el script de gestión:

```bash
# Ver estado
./scripts/manage-homelab.sh status

# Ver logs
./scripts/manage-homelab.sh logs

# Crear backup
./scripts/manage-homelab.sh backup

# Actualizar servicios
./scripts/manage-homelab.sh update

# Monitor en tiempo real
./scripts/manage-homelab.sh monitor

# Ayuda completa
./scripts/manage-homelab.sh help
```

Ver [scripts/README.md](scripts/README.md) para documentación completa de scripts.

## Troubleshooting
- Ver config final: `docker compose config`
- Logs servicios: `docker compose logs -f --tail=150`
- Ver sólo un servicio: `docker compose logs -f jellyfin`
- Caddy rutas: `docker compose logs -f caddy | grep <dominio>`

## Extensiones Futuras
- Monitoreo: Prometheus + cAdvisor + node-exporter (añadir a red backend).
- Notificaciones imagen: Diun.
- Offsite backups: contenedor restic (montar repositorio destino).

## Limitaciones
- Sin rollback automático (usa git revert).
- Watchtower (si activo) puede introducir cambios no probados → preferible fijar tags.
- Backups sólo DB Immich (otros servicios dependen de volúmenes/config que puedes snapshotear aparte).

## Licencia
MIT (ajusta según tus necesidades).

## Créditos / Notas
Basado en enfoque minimalista “GitOps-lite” para homelab. Ajusta dominios y rutas a tu entorno.