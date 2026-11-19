#!/usr/bin/env bash
# Task 1 - WordPress + MySQL with Docker (run step by step, or all at once)
set -e

# 1. Pull official images
docker pull mysql:8.0
docker pull wordpress:latest

# 2. Dedicated network
docker network create vr-net

# 3. MySQL with named volume
docker volume create vr-db-data
docker run -d \
  --name vr-mysql \
  --network vr-net \
  -e MYSQL_ROOT_PASSWORD=rootpass123 \
  -e MYSQL_DATABASE=vehiclerental_db \
  -e MYSQL_USER=vruser \
  -e MYSQL_PASSWORD=vrpass123 \
  -v vr-db-data:/var/lib/mysql \
  --restart unless-stopped \
  mysql:8.0

echo "Waiting for MySQL to be ready..."
until docker exec vr-mysql mysqladmin ping -uroot -prootpass123 --silent 2>/dev/null; do
  sleep 2
done
echo "MySQL is ready."

# 4. WordPress on the same network
docker volume create vr-wp-data
docker run -d \
  --name vr-wordpress \
  --network vr-net \
  -e WORDPRESS_DB_HOST=vr-mysql:3306 \
  -e WORDPRESS_DB_NAME=vehiclerental_db \
  -e WORDPRESS_DB_USER=vruser \
  -e WORDPRESS_DB_PASSWORD=vrpass123 \
  -v vr-wp-data:/var/www/html \
  -p 8080:80 \
  --restart unless-stopped \
  wordpress:latest

# 5. Verify
docker ps --filter "name=vr-"
docker inspect -f '{{.Name}} -> {{.State.Status}}' vr-mysql vr-wordpress
docker logs --tail 10 vr-mysql
docker logs --tail 10 vr-wordpress
echo "Open http://localhost:8080 to finish the WordPress setup."