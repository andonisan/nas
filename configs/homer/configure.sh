#!/bin/bash
# Script para configurar Homer con el dominio correcto

CONFIG_FILE="$1"
DOMAIN="$2"

if [ -z "$CONFIG_FILE" ] || [ -z "$DOMAIN" ]; then
    echo "Uso: $0 <config_file> <domain>"
    exit 1
fi

echo "Configurando Homer para dominio: $DOMAIN"

# Reemplazar home.arpa con el dominio correcto
sed -i "s/home\.arpa/$DOMAIN/g" "$CONFIG_FILE"

echo "Homer configurado correctamente"
