#!/bin/bash
# Setup script — run as root on the VPS
# Usage: bash setup.sh

set -e

APP_DIR="/opt/crossfitmpo-dashboard"
SERVICE="crossfitmpo-dashboard"

echo "=== 1. Instalando dependencias del sistema ==="
apt-get update -qq
apt-get install -y python3 python3-venv python3-pip nginx certbot python3-certbot-nginx

echo "=== 2. Creando directorio de la aplicación ==="
mkdir -p "$APP_DIR"
mkdir -p /var/log/crossfitmpo-dashboard

echo "=== 3. Copiando ficheros ==="
# Adjust source path if needed
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cp -r "$SCRIPT_DIR"/app.py \
       "$SCRIPT_DIR"/wsgi.py \
       "$SCRIPT_DIR"/config.py \
       "$SCRIPT_DIR"/sheets.py \
       "$SCRIPT_DIR"/requirements.txt \
       "$SCRIPT_DIR"/templates \
       "$SCRIPT_DIR"/static \
       "$APP_DIR"/

echo "=== 4. Creando entorno virtual ==="
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install -q --upgrade pip
"$APP_DIR/venv/bin/pip" install -q -r "$APP_DIR/requirements.txt"

echo "=== 5. Ajustando permisos ==="
chown -R www-data:www-data "$APP_DIR"
chown -R www-data:www-data /var/log/crossfitmpo-dashboard

echo "=== 6. Instalando servicio systemd ==="
cp "$SCRIPT_DIR/deploy/crossfitmpo-dashboard.service" /etc/systemd/system/
echo ""
echo "  ⚠️  Edita el SECRET_KEY en /etc/systemd/system/crossfitmpo-dashboard.service"
echo "     antes de continuar."
echo ""
read -p "  Pulsa ENTER cuando hayas editado el SECRET_KEY..."
systemctl daemon-reload
systemctl enable "$SERVICE"
systemctl start  "$SERVICE"

echo "=== 7. Configurando Nginx ==="
cp "$SCRIPT_DIR/deploy/nginx.conf" /etc/nginx/sites-available/crossfitmpo-dashboard
ln -sf /etc/nginx/sites-available/crossfitmpo-dashboard \
        /etc/nginx/sites-enabled/crossfitmpo-dashboard
nginx -t
systemctl reload nginx

echo "=== 8. Certificado SSL (Let's Encrypt) ==="
certbot --nginx -d dashboard.crossfitmpo.com --non-interactive --agree-tos -m admin@crossfitmpo.com || \
  echo "  ⚠️  Ejecuta manualmente: certbot --nginx -d dashboard.crossfitmpo.com"

echo ""
echo "✅  Dashboard desplegado en https://dashboard.crossfitmpo.com"
echo "   Estado del servicio:"
systemctl status "$SERVICE" --no-pager -l
