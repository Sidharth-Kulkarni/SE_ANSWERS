# 1. Docker: Multi-Container Application (WordPress + MySQL)

**Goal:** WordPress (frontend) and MySQL (backend) run as two containers on one user-defined Docker network. MySQL data sits in a named volume, so it survives container restarts and replacement.

Names used throughout:

| Thing | Name |
|-------|------|
| Network | `vr-net` |
| MySQL container | `vr-mysql` |
| WordPress container | `vr-wordpress` |
| DB volume | `vr-db-data` |
| WP files volume (optional) | `vr-wp-data` |
| Database / user / password | `vehiclerental_db` / `vruser` / `vrpass123` |
| MySQL root password | `rootpass123` |

All the commands are also in [`commands.bat`](commands.bat). Double-click it or run `commands.bat` in CMD.

> **Works in CMD and PowerShell.** Every command is on one line. Copy one line at a time. The "Expected" notes under each block are not commands.

---

## Step 1: Download the official images

```
docker pull mysql:8.0
docker pull wordpress:latest
docker images
```

Expected: `mysql 8.0` and `wordpress latest` appear in the list.

## Step 2: Create a dedicated network

```
docker network create vr-net
docker network ls
```

Expected: `vr-net` with driver `bridge`.

A user-defined bridge network gives the containers **built-in DNS**, so WordPress can reach MySQL by the name `vr-mysql`. The default `bridge` network doesn't do this.

## Step 3: Run MySQL with a database, a user and a named volume

```
docker volume create vr-db-data
docker run -d --name vr-mysql --network vr-net -e MYSQL_ROOT_PASSWORD=rootpass123 -e MYSQL_DATABASE=vehiclerental_db -e MYSQL_USER=vruser -e MYSQL_PASSWORD=vrpass123 -v vr-db-data:/var/lib/mysql --restart unless-stopped mysql:8.0
```

- `-v vr-db-data:/var/lib/mysql`: `/var/lib/mysql` is where MySQL keeps its data files. Mounting the named volume there makes the data persistent.
- No `-p` flag is needed. Only WordPress talks to MySQL, and it does so over `vr-net`.

Wait until MySQL is ready before starting WordPress:

```
docker logs -f vr-mysql
```

Expected: wait for a line containing `ready for connections` ... `port: 3306`, then press **Ctrl+C**. A first `ready for connections ... port: 0` line is MySQL's temporary setup server, so keep waiting for the `port: 3306` one.

## Step 4: Run WordPress on the same network

```
docker volume create vr-wp-data
docker run -d --name vr-wordpress --network vr-net -e WORDPRESS_DB_HOST=vr-mysql:3306 -e WORDPRESS_DB_NAME=vehiclerental_db -e WORDPRESS_DB_USER=vruser -e WORDPRESS_DB_PASSWORD=vrpass123 -v vr-wp-data:/var/www/html -p 8080:80 --restart unless-stopped wordpress:latest
```

- `WORDPRESS_DB_HOST=vr-mysql`: the **container name** of MySQL, resolved by Docker DNS.
- `WORDPRESS_DB_NAME`, `WORDPRESS_DB_USER` and `WORDPRESS_DB_PASSWORD` **must match** the `MYSQL_*` values from Step 3.
- `-p 8080:80`: host port 8080 maps to Apache's port 80 inside the container.
- `-v vr-wp-data:/var/www/html` (optional) also keeps themes, plugins and uploads.

## Step 5: Use the portal and verify with Docker commands

1. Open **http://localhost:8080**.
2. Finish the WordPress install wizard: pick a language, then enter a Site Title ("Vehicle Rental Portal"), an admin username, a password and an email.
3. Log in at `http://localhost:8080/wp-admin` and add sample content, for example:
   - **Page "Vehicle Categories":** Hatchback (₹1,200/day), Sedan (₹1,800/day), SUV (₹2,500/day), Bikes (₹500/day)
   - **Page "Rental Locations":** Narayanguda, Ameerpet, Gachibowli, Hyderabad Airport
   - **Page "Rental Policies":** Valid driving licence required, ₹5,000 refundable deposit, fuel-to-fuel policy, free cancellation up to 24 h before pickup
   - **Page "Contact Us":** phone, email, office address
4. Check the containers and their logs:

```
docker ps
docker ps -a --filter "name=vr-"
docker inspect -f "{{.Name}} {{.State.Status}}" vr-mysql vr-wordpress
docker logs --tail 20 vr-mysql
docker logs --tail 20 vr-wordpress
docker network inspect vr-net
docker volume inspect vr-db-data
```

Expected:
- `docker ps`: both containers show `Up`
- `docker inspect`: `/vr-mysql running` and `/vr-wordpress running`
- MySQL logs: `ready for connections`
- WordPress logs: Apache started, with `GET /` requests from your browser
- `network inspect`: both containers listed under `Containers`
- `volume inspect`: the `Mountpoint` where the data is stored

Optional: confirm WordPress tables exist in MySQL:

```
docker exec -it vr-mysql mysql -uvruser -pvrpass123 -e "USE vehiclerental_db; SHOW TABLES;"
```

Expected: `wp_posts`, `wp_options`, `wp_users` and other WordPress tables.

### Proving persistence (good to demo)

Delete the MySQL container, then create a brand-new one using the same volume:

```
docker rm -f vr-mysql
docker run -d --name vr-mysql --network vr-net -e MYSQL_ROOT_PASSWORD=rootpass123 -e MYSQL_DATABASE=vehiclerental_db -e MYSQL_USER=vruser -e MYSQL_PASSWORD=vrpass123 -v vr-db-data:/var/lib/mysql --restart unless-stopped mysql:8.0
```

Wait a few seconds and refresh http://localhost:8080. All your pages are still there.

### Common errors

| Error | Fix |
|-------|-----|
| `network vr-net not found` | Run `docker network create vr-net` first |
| `container name "/vr-mysql" is already in use` | `docker rm -f vr-mysql`, then run again |
| `port is already allocated` | Use another host port, e.g. `-p 8081:80` |
| Browser shows "Error establishing a database connection" | MySQL isn't ready yet. Wait, then `docker restart vr-wordpress` |
| `'--name' is not recognized...` | You pasted a multi-line command. Use the one-line versions above |

### Cleanup

```
docker rm -f vr-wordpress vr-mysql
docker network rm vr-net
docker volume rm vr-db-data vr-wp-data
```

The last command deletes the data, so only run it if you mean to.

> **Alternative:** [`docker-compose.yml`](docker-compose.yml) does the same thing in one file (`docker compose up -d`). The lab asks for the individual steps, so show the `docker run` approach in the exam.

---

## Scenario-based Questions

**Q1. What problem may occur if the WordPress container starts before the MySQL service is ready?**
MySQL needs several seconds on first start to initialise its data directory and create the database and user. If WordPress starts first, its connection attempts fail and the browser shows **"Error establishing a database connection."** The WordPress logs may also show `MySQL Connection Error: (2002) Connection refused`. A container being "running" does not mean the service inside it is "ready". The fix is to start MySQL first and wait for `ready for connections` in `docker logs`. You can also restart WordPress with `docker restart vr-wordpress`, give it `--restart unless-stopped`, or in Compose add a MySQL `healthcheck` with `depends_on: condition: service_healthy`.

**Q2. How can WordPress connect to the MySQL container by using its container name instead of a changing IP address?**
Both containers are attached to the same **user-defined network** (`vr-net`). Docker runs an embedded DNS server (127.0.0.11) on such networks, and it resolves each container's **name** to its current IP. Setting `WORDPRESS_DB_HOST=vr-mysql:3306` therefore keeps working even when MySQL is recreated and gets a new IP. The default `bridge` network has no name resolution, which is why a dedicated network is created.

**Q3. Why must the database name and login credentials configured for WordPress match those configured in MySQL?**
`MYSQL_DATABASE`, `MYSQL_USER` and `MYSQL_PASSWORD` tell MySQL which database and account to create, and grant that user rights only on that database. WordPress writes its `WORDPRESS_DB_*` values into `wp-config.php` and uses them to log in. A wrong user or password gives *Access denied for user*. A wrong database name gives *Unknown database*, or the user has no privileges on it. Either way WordPress shows the database connection error and can't store pages.

**Q4. What change would you make if the selected host port for the WordPress website is already being used by another application?**
Docker refuses to start the container with `Bind for 0.0.0.0:8080 failed: port is already allocated`. Change only the **host** side of the mapping and keep the container side at 80: `docker rm -f vr-wordpress`, then rerun with e.g. `-p 8081:80` and open `http://localhost:8081`. You can find what holds the port with `netstat -ano | findstr :8080` on Windows (the last column is the PID, which you can look up in Task Manager), or with `docker ps` if it's another container. If WordPress was already installed under the old port, also update **Settings → General → Site URL**, because WordPress stores its URL in the database.

**Q5. How do named volumes help the company retain portal information when the database container is replaced?**
A container's writable layer is deleted together with the container. A **named volume** (`vr-db-data`) is managed by Docker separately from any container (under `/var/lib/docker/volumes/`). MySQL's data directory `/var/lib/mysql` is mounted on that volume, so all tables (pages, posts, users, settings) are written outside the container. When the container is removed, upgraded (e.g. new `mysql:8.0` image) or recreated, the new container mounts the same volume and finds all the data intact. The data is only lost if someone explicitly runs `docker volume rm`.