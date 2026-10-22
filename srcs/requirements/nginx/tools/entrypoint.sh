#!/bin/bash
set -e

if [ ! -f /etc/nginx/ssl/inception.crt ]; then
    echo "[nginx] Generating self-signed certificate..."
    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/inception.key \
        -out /etc/nginx/ssl/inception.crt \
        -subj "/C=TR/ST=Istanbul/L=Istanbul/O=42/OU=student/CN=${DOMAIN_NAME}"
    echo "[nginx] Certificate created."
fi

envsubst '${DOMAIN_NAME}' \
    < /etc/nginx/conf.d/default.conf.template \
    > /etc/nginx/conf.d/default.conf

echo "[nginx] Starting nginx..."
exec nginx -g "daemon off;"
