# User documentation

This document explains how to run and use the Inception stack. It assumes the
machine has already been set up — see `DEV_DOC.md` for the initial setup.

## What the stack provides

Three services run in separate containers:

| Service     | Role                                                    |
|-------------|---------------------------------------------------------|
| `nginx`     | Entry point. Serves the site over HTTPS on port 443      |
| `wordpress` | Runs the WordPress PHP code through php-fpm             |
| `mariadb`   | Stores posts, users and settings                        |

Only NGINX is reachable from outside. The other two are only reachable from
within the internal Docker network.

## Starting and stopping

All commands are run from the project root.

```bash
make           # build if needed and start all services
make down      # stop and remove the containers (data is kept)
make stop      # pause the containers without removing them
make start     # resume paused containers
make logs      # follow the logs, Ctrl+C to stop following
```

The containers restart automatically if they crash, and after a reboot of the
host.

To check that everything is running:

```bash
docker ps
```

You should see three containers with status `Up`, and `0.0.0.0:443->443/tcp`
on the `nginx` row.

## Accessing the site

Open a browser and go to:
https://sungor.42.fr


The certificate is self-signed, so the browser shows a security warning the
first time. Choose *Advanced* and then *Accept the risk and continue*. The
connection is encrypted; the warning only means the certificate was not issued
by a recognised authority.

The address must resolve to the local machine. If the page does not load,
check that `/etc/hosts` contains:
127.0.0.1 sungor.42.fr

HTTP on port 80 is intentionally closed. Only HTTPS works.

## Accessing the admin panel
https://sungor.42.fr/wp-admin


Log in with the administrator account. From there you can publish posts,
change the theme, manage comments and add users.

## Accounts and credentials

Two WordPress accounts exist:

| Username     | Role          | Can do                                  |
|--------------|---------------|-----------------------------------------|
| `sungorboss` | administrator | Everything, including site settings      |
| `editor`     | author        | Write and publish their own posts only   |

Passwords are **not** stored in the repository. They are read from files in
`secrets/`, which is excluded from git:

| File                       | Password for                      |
|----------------------------|-----------------------------------|
| `credentials.txt`          | WordPress administrator           |
| `wp_user_password.txt`     | The second WordPress user         |
| `db_password.txt`          | The database user WordPress uses  |
| `db_root_password.txt`     | The MariaDB root account          |

To read one:

```bash
cat secrets/credentials.txt
```

### Changing a password

Changing the WordPress admin password is done from the admin panel, under
*Users*. Changing a value in `secrets/` after installation has no effect,
because the accounts already exist in the database.

To apply a new password from the files, the installation has to be redone:

```bash
make fclean
make
```

This deletes all data, including posts.

## Checking that the services work

```bash
# the site answers over HTTPS
curl -kI https://sungor.42.fr

# port 80 is closed, as intended
curl -I http://sungor.42.fr

# the database is reachable from inside the network
docker exec -it mariadb mariadb -u wpuser -p -e "SHOW DATABASES;"

# the two WordPress users exist
docker exec -it wordpress wp user list --allow-root
```

To read the logs of one service:

```bash
docker logs nginx
docker logs wordpress
docker logs mariadb
```

## Where the data lives

| Content                      | Location on the host              |
|------------------------------|-----------------------------------|
| Database                     | `/home/sungor/data/mariadb`       |
| WordPress files and uploads  | `/home/sungor/data/wordpress`     |

These directories survive `make down`. They are only removed by `make fclean`.
To back up the site, copy both directories while the containers are stopped.
