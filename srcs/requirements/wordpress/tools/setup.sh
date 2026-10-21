#!/bin/bash
set -e

DB_PASS=$(cat /run/secrets/db_password | tr -d '\n')
WP_ADMIN_PASS=$(cat /run/secrets/credentials | tr -d '\n')
WP_USER_PASS=$(cat /run/secrets/wp_user_password | tr -d '\n')

echo "[wp] Waiting for MariaDB..."
for i in $(seq 1 30); do
    if mariadb-admin ping -h mariadb -u "${MYSQL_USER}" -p"${DB_PASS}" --silent 2>/dev/null; then
        echo "[wp] MariaDB is ready."
        break
    fi
    if [ "$i" = "30" ]; then
        echo "[wp] MariaDB did not respond in time."
        exit 1
    fi
    sleep 1
done

cd /var/www/html

if [ ! -f wp-config.php ]; then
    echo "[wp] Installing WordPress..."

    wp core download --allow-root

    wp config create \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASS}" \
        --dbhost=mariadb \
        --allow-root

    wp core install \
        --url="https://${DOMAIN_NAME}" \
        --title="Inception" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASS}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email \
        --allow-root

    wp user create "${WP_USER}" "${WP_USER_EMAIL}" \
        --role=author \
        --user_pass="${WP_USER_PASS}" \
        --allow-root

    chown -R www-data:www-data /var/www/html
    echo "[wp] WordPress installed."
else
    echo "[wp] WordPress already installed, skipping."
fi

exec php-fpm8.2 -F
