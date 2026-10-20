#!/bin/bash
set -e

DB_ROOT_PASS=$(cat /run/secrets/db_root_password | tr -d '\n')
DB_PASS=$(cat /run/secrets/db_password | tr -d '\n')

if [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then
    echo "[init] Setting up database..."

    mariadb-install-db --user=mysql --datadir=/var/lib/mysql > /dev/null

    cat > /tmp/init.sql <<EOF
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';
DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS ''@'%';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
EOF

    echo "[init] Starting server with init file..."
    exec mysqld --user=mysql --init-file=/tmp/init.sql
fi

echo "[init] Database already exists, skipping setup."
exec mysqld --user=mysql
