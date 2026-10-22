*This project has been created as part of the 42 curriculum by sungor.*

# Inception

## Description

Inception is a system administration project built around Docker. It sets up a
small infrastructure of three services, each running in its own container,
orchestrated with Docker Compose and launched from a single Makefile.

The stack serves a WordPress site over HTTPS:
Internet --443--> NGINX --9000--> WordPress (php-fpm) --3306--> MariaDB

- **NGINX** is the only entry point. It terminates TLS (TLSv1.2 / TLSv1.3),
  serves static files and forwards PHP requests over FastCGI.
- **WordPress + php-fpm** executes the PHP code. No web server is installed in
  this container.
- **MariaDB** stores the site data.

All images are built from `debian:bookworm` with custom Dockerfiles. No
pre-built application image is pulled from DockerHub.

Two named volumes keep the database and the site files on the host under
`/home/sungor/data`, so data survives a container rebuild. The containers
communicate over a dedicated bridge network and resolve each other by service
name through Docker's internal DNS.

## Instructions

### Requirements

- A virtual machine running Debian 12 (bookworm)
- Docker Engine and the Docker Compose plugin
- The domain pointing to the loopback address:

```bash
echo "127.0.0.1 sungor.42.fr" | sudo tee -a /etc/hosts
```

### Configuration

Two things are not tracked by git and must exist before the first build:

1. `srcs/.env` — non-sensitive settings (domain, database name, usernames)
2. `secrets/` — one file per password:
   - `db_root_password.txt`
   - `db_password.txt`
   - `credentials.txt`
   - `wp_user_password.txt`

### Build and run

```bash
make          # build the images and start everything
make down     # stop and remove the containers
make logs     # follow the logs
make fclean   # remove containers, images, volumes and data
make re       # full rebuild from scratch
```

Then open `https://sungor.42.fr` in a browser. The certificate is self-signed,
so the browser will warn about it; this is expected.

See `USER_DOC.md` for day-to-day usage and `DEV_DOC.md` for development
details.

## Project description

### Design choices

**One process per container.** Each container runs its service as PID 1 in the
foreground, with no process supervisor and no idle-loop workarounds such as
`tail -f` or `sleep infinity`. Entrypoint scripts end with `exec`, so the
service replaces the shell and receives signals directly. `docker stop` then
shuts the service down cleanly instead of having it killed after the grace
period.

**Idempotent entrypoints.** Volumes outlive containers, so each entrypoint
checks whether initialisation has already happened — MariaDB looks for its
database directory, WordPress looks for `wp-config.php` — and skips setup when
it has. The containers can be recreated any number of times without errors.

**Readiness over ordering.** `depends_on` only guarantees start order, not that
a service is accepting connections. The WordPress entrypoint polls MariaDB with
a bounded retry loop (30 attempts, one second apart) and exits with an error if
the database never answers, letting the restart policy try again.

**Base image.** `debian:bookworm` — the penultimate stable Debian release, as
required. Pinning the codename instead of using `latest` keeps builds
reproducible over time.

### Virtual machines vs Docker

A virtual machine emulates hardware and boots a complete operating system with
its own kernel on top of a hypervisor. That isolation is strong, but it costs
gigabytes of disk, a fixed slice of RAM and a full boot sequence.

A container is an isolated process. It gets its own filesystem, process table
and network interface through kernel namespaces and cgroups, but it shares the
host kernel. There is no second kernel to boot, so startup is measured in
milliseconds and the image is measured in megabytes.

The trade-off is isolation depth versus cost. A VM can run a different kernel
or a different operating system; a container cannot. For running several
services of the same stack on one machine, containers are far cheaper — this
project runs three of them inside a VM that itself took minutes to install.

### Docker secrets vs environment variables

Environment variables are readable. `docker inspect` prints them, they are
inherited by every child process, and they can leak into logs or crash dumps.
They are fine for configuration — a domain name, a database name, a username.

Secrets are mounted into the container as files under `/run/secrets/`. They do
not appear in `docker inspect`, they are not part of the process environment,
and they are never written into the image. The entrypoint reads the file when
it needs the value.

This project splits the two accordingly: `srcs/.env` holds the non-sensitive
settings, `secrets/` holds the four passwords, and both are excluded from git.

### Docker network vs host network

With the host driver a container shares the host's network namespace: its
listeners bind directly to the host's interfaces and ports. There is no network
isolation left, port conflicts become possible, and — important here — Docker's
embedded DNS does not apply, so containers cannot address each other by service
name.

With a user-defined bridge network, each container gets its own namespace and
address on a private subnet, reachable from the host only through explicitly
published ports. Docker runs a DNS resolver on that network, which is what
makes `fastcgi_pass wordpress:9000` and `DB_HOST=mariadb` work: names are
stable, container IP addresses are not.

This project defines its own bridge network and publishes exactly one port,
443 on NGINX. MariaDB and php-fpm listen only inside the network.

### Docker volumes vs bind mounts

A bind mount maps a host path straight into the container. It is quick to set
up, but the container is then tied to the host's directory layout, and
ownership and permissions come from the host unchanged.

A named volume is managed by Docker: it appears in `docker volume ls`, can be
inspected, backed up and moved, and its lifecycle is independent of any single
container. Drivers and driver options give control over where and how the data
is actually stored.

This project uses named volumes, as required. The subject also asks for the
data to live under `/home/login/data`, which is handled with `driver_opts`
(`type: none`, `o: bind`, `device: /home/sungor/data/...`). The volumes remain
Docker-managed objects; only the backing location is pinned.

## Resources

### Documentation

- Docker documentation — Dockerfile reference, Compose file reference,
  networking, volumes and secrets: https://docs.docker.com
- Docker: *Run multiple processes in a container* and the discussion of PID 1
  and signal handling in containers
- MariaDB Knowledge Base — server configuration, `mariadb-install-db`,
  `--init-file`, user and privilege management: https://mariadb.com/kb
- PHP manual — FPM configuration and pool directives:
  https://www.php.net/manual/en/install.fpm.configuration.php
- NGINX documentation — `ngx_http_ssl_module` and `ngx_http_fastcgi_module`:
  https://nginx.org/en/docs/
- WP-CLI handbook — `core download`, `config create`, `core install`,
  `user create`: https://developer.wordpress.org/cli/commands/
- OpenSSL `req` manual page, for generating the self-signed certificate
- Debian wiki and the `debian:bookworm` image documentation

### Videos and articles

Alongside the official documentation I watched introductory videos and read
walkthroughs on containers and Docker Compose to build intuition before writing
any code: explanations of the difference between images and containers, how
layers and the build cache work, and how NGINX and php-fpm communicate over
FastCGI. These were used to understand the concepts, not to copy
configuration.

### Use of artificial intelligence

I used an AI assistant as a tutor and as a second pair of eyes:

- Explaining parts of the documentation I did not follow at first — PID 1 and
  signal handling, build time versus run time, image layers and the build
  cache, bridge networking and Docker's DNS, named volumes versus bind mounts.
- Planning the work and breaking it into stages.
- Drafting configuration I then reviewed and adapted line by line.
- Recalling command syntax and flags I kept forgetting.
- Designing the harder tests — crash and restart behaviour, data persistence
  across a rebuild, verifying that only port 443 is reachable.
- Debugging two failures: database initialisation in `--bootstrap` mode, and a
  login that was being shadowed by the leftover anonymous MariaDB account.

Everything in this repository was reviewed, tested and can be explained.
