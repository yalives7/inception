# Developer documentation

## Repository layout

.
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── secrets/ # not tracked by git
│ ├── credentials.txt
│ ├── db_password.txt
│ ├── db_root_password.txt
│ └── wp_user_password.txt
└── srcs/
├── .env # not tracked by git
├── docker-compose.yml
└── requirements/
├── mariadb/
│ ├── Dockerfile
│ ├── .dockerignore
│ ├── conf/99-inception.cnf
│ └── tools/init.sh
├── wordpress/
│ ├── Dockerfile
│ ├── .dockerignore
│ ├── conf/www.conf
│ └── tools/setup.sh
└── nginx/
├── Dockerfile
├── .dockerignore
├── conf/default.conf
└── tools/entrypoint.sh


Each service follows the same pattern: a Dockerfile, a configuration file that
overrides a Debian default, and an entrypoint script that performs first-run
setup and then replaces itself with the service via `exec`.

## Setting up from scratch

### Prerequisites

A virtual machine running Debian 12 (bookworm). Install Docker from the
official repository — the version in Debian's own repository is older and does
not ship the Compose v2 plugin:

```bash
sudo apt-get update
sudo apt-get install -y curl ca-certificates git make

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg \
     -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) \
signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian \
$(. /etc/os-release && echo $VERSION_CODENAME) stable" \
| sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
     docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER
```

Log out and back in for the group change to apply.

### Domain resolution

```bash
echo "127.0.0.1 sungor.42.fr" | sudo tee -a /etc/hosts
```

### Configuration files

Neither of these is in the repository; both must be created before the first
build.

`srcs/.env`:

DOMAIN_NAME=sungor.42.fr

MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser

WP_ADMIN_USER=sungorboss
WP_ADMIN_EMAIL=sungor@student.42.fr
WP_USER=editor
WP_USER_EMAIL=editor@student.42.fr



No password belongs in this file. The admin username must not contain `admin`
or `administrator`.

`secrets/` — one password per file, no trailing content:

```bash
mkdir -p secrets
printf "<root password>"     > secrets/db_root_password.txt
printf "<db user password>"  > secrets/db_password.txt
printf "<wp admin password>" > secrets/credentials.txt
printf "<wp user password>"  > secrets/wp_user_password.txt
chmod 600 secrets/*.txt
```

`printf` is used instead of `echo` to avoid a trailing newline. The entrypoint
scripts strip newlines with `tr -d '\n'` anyway, so either works.

Both paths are listed in `.gitignore`. Verify before the first commit:

```bash
git status            # secrets/ and srcs/.env must not appear
git ls-files | grep -E "secrets|\.env"   # must return nothing
```

## Building and running

The Makefile wraps Docker Compose and creates the host directories the volumes
bind to.

| Target   | Effect                                                        |
|----------|---------------------------------------------------------------|
| `all`    | Default target, runs `up`                                      |
| `build`  | Builds the three images without starting them                  |
| `up`     | Creates the data directories, builds and starts in background  |
| `down`   | Stops and removes containers and the network. Data is kept     |
| `stop`   | Pauses containers without removing them                        |
| `start`  | Resumes paused containers                                      |
| `logs`   | Follows the logs of all services                               |
| `clean`  | `down` plus removal of volumes and images                      |
| `fclean` | `clean` plus deletion of the data directories                  |
| `re`     | `fclean` followed by `all`                                     |

Compose is always invoked with `-f srcs/docker-compose.yml`, so every target
works from the repository root.

## Managing containers and volumes

```bash
docker ps                      # running containers
docker ps -a                   # including stopped ones
docker images                  # built images
docker volume ls               # volumes
docker network ls              # networks

docker logs -f wordpress       # follow one service's logs
docker exec -it mariadb bash   # shell inside a container
docker inspect nginx           # full configuration of a container
docker volume inspect srcs_mariadb_volume
docker network inspect srcs_inception_network
```

To rebuild a single service:

```bash
docker compose -f srcs/docker-compose.yml up -d --build nginx
```

To check that a service runs as PID 1:

```bash
docker exec mariadb ps aux | head -3
docker exec nginx cat /proc/1/cmdline | tr '\0' ' '
```

The NGINX image has no `ps`, hence reading `/proc/1/cmdline` instead.

## Where the data is stored

Two named volumes, both pinned to a host directory with `driver_opts`:

| Volume             | Container path    | Host path                     |
|--------------------|-------------------|-------------------------------|
| `mariadb_volume`   | `/var/lib/mysql`  | `/home/sungor/data/mariadb`   |
| `wordpress_volume` | `/var/www/html`   | `/home/sungor/data/wordpress` |

```yaml
volumes:
  mariadb_volume:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/sungor/data/mariadb
```

They remain Docker-managed named volumes — they appear in `docker volume ls`
and can be inspected — while the backing directory is fixed, as the subject
requires. The host directories must exist before `up`; the Makefile creates
them.

`wordpress_volume` is mounted into both the `wordpress` and `nginx`
containers: php-fpm executes the PHP files, NGINX serves the static assets
from the same tree.

### How persistence works

The volumes outlive the containers, so both entrypoints are idempotent:

- `mariadb/tools/init.sh` checks for `/var/lib/mysql/${MYSQL_DATABASE}`
- `wordpress/tools/setup.sh` checks for `wp-config.php`

If the marker exists, setup is skipped and the service starts directly. This is
what makes `make down && make` safe: containers are recreated, data is not
touched.

`make fclean` is the only target that deletes data. It removes the contents of
both host directories.

## Notes for future changes

**Startup order.** `depends_on` only sequences container starts. The WordPress
entrypoint polls MariaDB with a bounded retry loop (30 attempts, one second
apart) and exits non-zero if the database never answers, so the restart policy
retries. Any new service that talks to the database needs the same treatment.

**Database initialisation.** The SQL runs through `mysqld --init-file`, not
`--bootstrap`. Bootstrap mode implies `--skip-grant-tables` and rejects
`CREATE USER` and `GRANT` with error 1290.

**Removing MariaDB users.** `mysql.user` is a view in MariaDB 10.4 and later,
so `DELETE FROM mysql.user` silently does nothing. Use `DROP USER` instead.
The leftover anonymous account matters: `''@'localhost'` matches more
specifically than `'wpuser'@'%'` and will shadow it for local connections.

**php-fpm listener.** `listen = 9000` rather than a Unix socket, because NGINX
runs in a separate container and cannot share a socket file. `clear_env = no`
keeps the variables from `.env` visible to the workers.

**NGINX configuration.** `conf/default.conf` is copied as a template and the
entrypoint substitutes `${DOMAIN_NAME}` with `envsubst` before starting NGINX,
since the server block needs the domain from `.env`. Debian's default site is
removed in the Dockerfile so that nothing listens on port 80.

**MariaDB configuration.** Debian's `50-server.cnf` is left in place; the
override lives in `99-inception.cnf`, which is read later and only sets
`bind-address = 0.0.0.0`.

