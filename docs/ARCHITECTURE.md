# Arquitectura (GitOps-lite)

## Objetivo
Homelab reproducible con mínimo scripting: un único compose.yaml + labels para reverse proxy + Actions para despliegue.

## Diagrama Conceptual (texto)
```
Usuarios -> Caddy (autodiscovery) -> (Homer | Jellyfin | Syncthing | Immich)
                                |
                                +--> backend (Redis, Postgres, ML, backups)
```

## Redes
- proxy: exposición HTTP/HTTPS
- backend (internal): capa de datos y ML

## Componentes Clave
| Componente | Rol | Notas |
|------------|-----|-------|
| Caddy Proxy | Reverse proxy dinámico | Genera hosts por labels |
| Homer | Dashboard ultra-ligero | Acceso principal - 15MB RAM |
| Jellyfin | Streaming multimedia | Aceleración HW opcional |
| Syncthing | Sincronización | Panel encapsulado |
| Postgres | DB Immich | Solo perfil photos, tuneado para 12GB RAM |
| Redis | Cache / cola Immich | Solo perfil photos |
| Immich Server | Fotos | Perfil photos, workers limitados |
| Immich ML | Indexación/ML | Controlada por env IMMICH_ML |
| pgbackups | Dump programado | Cron configurable |
| AdGuard Home | Bloqueo DNS/anuncios | Perfil network, bind localhost |
| Netdata | Métricas sistema | Perfil monitoring, acceso PID host |
| Uptime Kuma | Monitor uptime | Perfil monitoring |
| File Browser | Explorador web | Perfil files, alternativa ligera |
| Watchtower | Actualización automática | Perfil watchtower opcional |

## Perfiles
- **base**: servicios esenciales + proxy (caddy, homer, jellyfin, syncthing)
- **photos**: añade stack fotos (postgres, redis, immich-*, pgbackups)
- **network**: bloqueo DNS (adguardhome)
- **monitoring**: métricas y uptime (netdata, uptime-kuma)
- **files**: explorador web (filebrowser)
- **watchtower**: actualización automática

## Flujos Principales
1. Deploy:
   - Push a main
   - Action valida
   - Action via SSH sincroniza y hace compose up -d
2. Reverse proxy:
   - Caddy escucha Docker events → genera vhosts
3. Backups:
   - pgbackups ejecuta cron → dumps rotados

## Backups y Recuperación
| Elemento | Método | Restauración |
|----------|--------|--------------|
| DB Immich | Contenedor pgbackups | psql import dump |
| Medios / Fotos | Datos en host (bind mounts) | Copia/Snapshot FS |
| Config servicios | Volúmenes Docker | Reutilizar volumen / copy |

Recomendado: añadir contenedor restic para sync offsite del volumen de dumps y, si se desea, hash de medios.

## Seguridad
- Sin exposición de Postgres/Redis fuera de backend.
- Secrets mediante POSTGRES_PASSWORD_FILE.
- Minimizar uso de latest para entornos más críticos → fijar tags.

## Estrategia de Versionado
1. Inicialmente latest para rapidez.
2. Al estabilizar, fijar versiones exactas en compose y documentar upgrade.

## Escalabilidad / Evolución
- Añadir monitoreo (Prometheus + exporters) en red backend.
- Reemplazar Watchtower por Diun + PRs para cambios controlados.
- Migrar a LXC / VM sin cambios de estructura (solo mover repo y volúmenes).
- Añadir SSO (Authelia/Authentik) delante de Caddy si se abren servicios fuera de LAN.

## Riesgos y Mitigaciones
| Riesgo | Descripción | Mitigación |
|--------|-------------|------------|
| Update inesperado (Watchtower) | Imagen rota tras push upstream | Fijar tags / desactivar watchtower |
| Pérdida config DB | Dump programado falla | Monitorizar logs pgbackups / alerta |
| Exposición inadvertida | Caddy publica contenedor no esperado | No añadir labels caddy en servicios privados |

## Migración a Otro Host
1. Backup dumps + copiar bind mounts.
2. Clonar repo en nuevo host.
3. Replicar .env y secrets.
4. docker compose up -d (perfiles según necesidad).

## Limitaciones
- No hay rollback “snapshot” integrado (depende de git + compose).
- Backup de Postgres básico (no PITR).

## Próximos Pasos Sugeridos
- Añadir monitoreo opcional.
- Diun para notificaciones.
- Restic para offsite.

## Notas Finales
Modelo pensado para simplicidad y trazabilidad: cambiar infra = commit auditable.
