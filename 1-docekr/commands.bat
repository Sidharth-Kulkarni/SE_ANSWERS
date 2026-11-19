@echo off
REM Task 1 - WordPress + MySQL with Docker (Windows CMD)
REM Run from Command Prompt:  commands.bat

echo === 1. Pulling official images ===
docker pull mysql:8.0
docker pull wordpress:latest

echo === 2. Creating dedicated network ===
docker network create vr-net

echo === 3. Starting MySQL with named volume ===
docker volume create vr-db-data
docker run -d --name vr-mysql --network vr-net -e MYSQL_ROOT_PASSWORD=rootpass123 -e MYSQL_DATABASE=vehiclerental_db -e MYSQL_USER=vruser -e MYSQL_PASSWORD=vrpass123 -v vr-db-data:/var/lib/mysql --restart unless-stopped mysql:8.0

echo Waiting for MySQL to be ready (can take 30-60 seconds on first run)...
:waitmysql
timeout /t 3 /nobreak >nul
docker logs vr-mysql 2>&1 | findstr /C:"port: 3306" >nul
if errorlevel 1 goto waitmysql
echo MySQL is ready.

echo === 4. Starting WordPress on the same network ===
docker volume create vr-wp-data
docker run -d --name vr-wordpress --network vr-net -e WORDPRESS_DB_HOST=vr-mysql:3306 -e WORDPRESS_DB_NAME=vehiclerental_db -e WORDPRESS_DB_USER=vruser -e WORDPRESS_DB_PASSWORD=vrpass123 -v vr-wp-data:/var/www/html -p 8080:80 --restart unless-stopped wordpress:latest

echo === 5. Verifying ===
docker ps --filter "name=vr-"
docker inspect -f "{{.Name}} {{.State.Status}}" vr-mysql vr-wordpress
docker logs --tail 10 vr-mysql
docker logs --tail 10 vr-wordpress

echo.
echo Open http://localhost:8080 to finish the WordPress setup.
pause