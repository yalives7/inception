COMPOSE		= docker compose -f srcs/docker-compose.yml
DATA_DIR	= /home/sungor/data

all: up

build:
	mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress
	$(COMPOSE) build

up:
	mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop

start:
	$(COMPOSE) start

logs:
	$(COMPOSE) logs -f

clean: down
	$(COMPOSE) down --volumes --rmi all

fclean: clean
	sudo rm -rf $(DATA_DIR)/mariadb/* $(DATA_DIR)/wordpress/*

re: fclean all

.PHONY: all build up down stop start logs clean fclean re
