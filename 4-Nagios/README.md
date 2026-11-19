# 4. Nagios: Infrastructure and Application Monitoring

**Goal:** Run Nagios in Docker and monitor the Vehicle Rental infrastructure from one dashboard: server CPU, memory, disk and uptime, the web application over HTTP, and the MySQL database, each with WARNING and CRITICAL thresholds.

> **Works in CMD and PowerShell.** Every command is on one line. Copy one line at a time. The "Expected" notes under each block are not commands.

| File | Purpose |
|------|---------|
| [`vehicle-rental.cfg`](vehicle-rental.cfg) | Hosts, services, commands and thresholds |
| [`scripts/check_mem.sh`](scripts/check_mem.sh) | Plugin: memory used % |
| [`scripts/check_uptime.sh`](scripts/check_uptime.sh) | Plugin: server uptime / recent reboot |

### What gets monitored

| Host (container) | Service | WARNING | CRITICAL |
|------------------|---------|---------|----------|
| `vehicle-rental-server` (`vr-app`) | CPU Load (per core, 1/5/15 min) | 0.70 / 0.60 / 0.50 | 0.90 / 0.80 / 0.70 |
| | Memory Usage | ≥ 80 % used | ≥ 90 % used |
| | Disk Usage (`/`) | < 20 % free | < 10 % free |
| | Server Uptime | up < 30 min (recent reboot) | up < 5 min |
| | PING | > 100 ms or > 20 % loss | > 500 ms or > 60 % loss |
| | HTTP Vehicle Rental App | response > 2 s | > 5 s, non-200, or page text missing |
| | Tomcat Port 8080 | connect > 1 s | > 3 s or refused |
| `vehicle-rental-db` (`vr-mysql`) | MySQL Port 3306 | connect > 1 s | > 3 s or refused |

All containers share the Docker network **`vr-net`** from Task 1, so Nagios reaches them by container name.

---

## Step 0: Make sure the things to monitor are running

**MySQL** (from Task 1) must be running:

```
docker ps --filter "name=vr-mysql"
```

If it isn't listed, start it (create the network first if needed):

```
docker network create vr-net
docker run -d --name vr-mysql --network vr-net -e MYSQL_ROOT_PASSWORD=rootpass123 -e MYSQL_DATABASE=vehiclerental_db -e MYSQL_USER=vruser -e MYSQL_PASSWORD=vrpass123 -v vr-db-data:/var/lib/mysql --restart unless-stopped mysql:8.0
```

`network already exists` is fine and can be ignored.

**The Vehicle Rental app on Tomcat.** Use the `Dockerfile` from `03-kubernetes` placed in the root of the app repo (next to `pom.xml`):

```
cd VehicleRentalManagementSystem
docker build -t vehicle-rental:1.0 .
docker run -d --name vr-app --network vr-net -p 8082:8080 --restart unless-stopped vehicle-rental:1.0
```

Expected: http://localhost:8082/VehicleRentalManagement/ shows the Vehicle Rental home page. Port 8082 is used because WordPress already has 8080.

---

## Step 1: Pull and run Nagios, then log in

```
docker pull jasonrivers/nagios:latest
docker run -d --name nagios --network vr-net -p 8081:80 --restart unless-stopped jasonrivers/nagios:latest
docker ps --filter "name=nagios"
docker logs --tail 20 nagios
```

Expected: the container shows `Up`, and the logs show Apache and Nagios starting.

Open **http://localhost:8081** (if that page is blank, try http://localhost:8081/nagios) and log in:

- **Username:** `nagiosadmin`
- **Password:** `nagios`

Click **Hosts** in the left menu. Only `localhost` (the Nagios container itself) is monitored at this point.

## Step 2: Configure the hosts and services

Open CMD in the **`04-nagios`** folder of this repo, then copy the config and plugins into the container:

```
docker cp vehicle-rental.cfg nagios:/opt/nagios/etc/objects/vehicle-rental.cfg
docker cp scripts\check_mem.sh nagios:/opt/nagios/libexec/check_mem.sh
docker cp scripts\check_uptime.sh nagios:/opt/nagios/libexec/check_uptime.sh
```

Remove Windows line endings and set permissions. Windows may have saved the files with CRLF endings, which break Linux scripts:

```
docker exec nagios sed -i s/\r// /opt/nagios/etc/objects/vehicle-rental.cfg /opt/nagios/libexec/check_mem.sh /opt/nagios/libexec/check_uptime.sh
docker exec nagios chmod 644 /opt/nagios/etc/objects/vehicle-rental.cfg
docker exec nagios chmod 755 /opt/nagios/libexec/check_mem.sh /opt/nagios/libexec/check_uptime.sh
```

Register the new file in `nagios.cfg`. The command adds it only once, even if you run it again:

```
docker exec nagios sh -c "grep -q vehicle-rental.cfg /opt/nagios/etc/nagios.cfg || echo cfg_file=/opt/nagios/etc/objects/vehicle-rental.cfg >> /opt/nagios/etc/nagios.cfg"
```

Check the configuration, then restart Nagios to load it:

```
docker exec nagios /opt/nagios/bin/nagios -v /opt/nagios/etc/nagios.cfg
docker restart nagios
```

Expected from the check: `Total Warnings: 0`, `Total Errors: 0` and `Things look okay`. If you get errors, the message names the file and line number. Fix it, then repeat the `docker cp` and `sed` commands for that file.

What the config defines (see [`vehicle-rental.cfg`](vehicle-rental.cfg)):
- **Hosts:** `vehicle-rental-server` (address `vr-app`) and `vehicle-rental-db` (address `vr-mysql`, with the app server as its parent), grouped in hostgroup `vehicle-rental`
- **Commands:** `vr_check_load`, `vr_check_mem`, `vr_check_disk`, `vr_check_uptime`, `vr_check_ping`, `vr_check_http_app`, `vr_check_tcp`
- **Services:** the 8 services in the table above. They're checked every minute, and a problem must repeat on 3 checks before it becomes a HARD state that sends notifications.

## Step 3: CPU, memory, disk and uptime

These are the first four services on `vehicle-rental-server`. You can test each plugin by hand:

```
docker exec nagios /opt/nagios/libexec/check_load -r -w 0.70,0.60,0.50 -c 0.90,0.80,0.70
docker exec nagios /opt/nagios/libexec/check_mem.sh -w 80 -c 90
docker exec nagios /opt/nagios/libexec/check_disk -w 20% -c 10% -p /
docker exec nagios /opt/nagios/libexec/check_uptime.sh -w 30 -c 5
```

Expected, for example:
- `LOAD OK - scaled load average: 0.08, 0.05, 0.03 ...`
- `MEMORY OK - 42% used (3300 MB of 7800 MB) ...`
- `DISK OK - free space: / 40000MiB (70% ...`
- `UPTIME OK - up 0 days, 3 hours, 12 minutes ...`

In the dashboard go to **Services**. All four show **OK** (green) with the same text in Status Information.

> The app runs in a container, so these checks measure the **Docker host** that runs it. The Nagios container shares the same host kernel, so `/proc/loadavg`, `/proc/meminfo` and `/proc/uptime` show that machine. To monitor a separate physical server, install an agent such as **NRPE** or **NCPA** on it and run the same checks remotely.

## Step 4: HTTP check and MySQL check

Test by hand:

```
docker exec nagios /opt/nagios/libexec/check_http -H vr-app -p 8080 -u /VehicleRentalManagement/ -s "Vehicle Rental" -w 2 -c 5
docker exec nagios /opt/nagios/libexec/check_tcp -H vr-mysql -p 3306 -w 1 -c 3
```

Expected:
- `HTTP OK: HTTP/1.1 200 ... - 0.012 second response time ...`
- `TCP OK - 0.001 second response time on vr-mysql port 3306 ...`

The HTTP check passes only if the page returns **200** *and* contains the text **"Vehicle Rental"**. A Tomcat error page fails it even though Tomcat itself is up. The MySQL check confirms the database is accepting connections on 3306.

**Optional real MySQL login check:** see whether the plugin exists:

```
docker exec nagios ls /opt/nagios/libexec/check_mysql
```

If it exists, remove the `#` signs in front of the two `vr_check_mysql` blocks in `vehicle-rental.cfg`, then copy the file in again (repeat the Step 2 commands) and restart.

## Step 5: WARNING and CRITICAL thresholds (with a demo)

The thresholds are the `!`-separated arguments in each `check_command` line of `vehicle-rental.cfg` (summarised in the table at the top). Nagios uses the plugin's exit code: **0 = OK, 1 = WARNING, 2 = CRITICAL, 3 = UNKNOWN**.

**Show a CRITICAL:** stop the application container:

```
docker stop vr-app
```

Within 1–3 minutes, `HTTP Vehicle Rental App` and `Tomcat Port 8080` go **CRITICAL** (red) and the host `vehicle-rental-server` goes **DOWN**. `vehicle-rental-db` shows **UNREACHABLE**, because the app server is its parent. To refresh a check immediately, click the service, then **Re-schedule the next check of this service** → **Commit**.

Bring it back:

```
docker start vr-app
```

Everything returns to **OK** (green) and Nagios logs a RECOVERY.

**Show a WARNING:** run a plugin with a deliberately low warning threshold:

```
docker exec nagios /opt/nagios/libexec/check_mem.sh -w 1 -c 99
```

Expected: `MEMORY WARNING - ...`, exit code 1. To see it on the dashboard, change `vr_check_mem!80!90` to `vr_check_mem!1!99` in the cfg, copy it in, restart, then revert the change afterwards.

Useful dashboard pages: **Tactical Overview** (one-page summary), **Services** (all checks), **Problems → Services (Unhandled)**, **Reports → Alerts → History**.

### Common errors

| Error | Fix |
|-------|-----|
| `/bin/sh^M: bad interpreter` or `(Return code of 127 is out of bounds)` | The script has Windows line endings. Run the `sed -i s/\r//` command from Step 2 again, then the `chmod 755` command |
| Service shows `(Return code of 126...)` | The script isn't executable. Run the `chmod 755` command |
| Hosts DOWN with `check_ping: Invalid hostname` / `Name or service not known` | Nagios isn't on `vr-net`. Run `docker network connect vr-net nagios`, or the target container isn't running |
| Config check reports `Error: Could not find any host matching ...` | A host name typo in the cfg |
| `HTTP CRITICAL - pattern not found` | The page loaded but doesn't contain "Vehicle Rental". Check http://localhost:8082/VehicleRentalManagement/ |

### Cleanup

```
docker rm -f nagios vr-app
```

---

## Scenario-based Questions

**Q1. How can Nagios help the administrator detect a server resource problem before the rental portal becomes unavailable?**
Nagios checks CPU load, memory, disk space and uptime every minute against **two levels** of thresholds. The **WARNING** level is set well below the danger point, e.g. memory 80 %, disk below 20 % free, or load 0.7 per core. When a resource crosses it, the dashboard turns yellow and the admin gets a notification while the portal is still working. The admin can then act early: free disk space, restart a leaking Tomcat, or add capacity. That happens before the **CRITICAL** level (memory 90 %, disk below 10 %) is reached, where customers would start seeing slow pages or failures. Performance data and the alert history also show trends such as disk filling up day by day, so problems can be predicted and planned for.

**Q2. When would a service be reported as WARNING rather than CRITICAL?**
**WARNING** (exit code 1) means a value has crossed the first threshold but the service still works, so attention is needed soon. **CRITICAL** (exit code 2) means the second threshold is crossed or the service has failed, so action is needed now. In this setup:
- Memory 85 % → WARNING. Memory 93 % → CRITICAL.
- The HTTP page loads in 3 s → WARNING (slow). It takes over 5 s, returns 404/500, or the page text is missing → CRITICAL.
- MySQL connects in 1.5 s → WARNING. The connection is refused → CRITICAL.
- The server rebooted 20 minutes ago → WARNING. It rebooted 2 minutes ago → CRITICAL.

A problem must repeat on `max_check_attempts` (3) consecutive checks before it becomes a HARD state and sends a notification. This avoids alerts for brief spikes.

**Q3. How can an HTTP service check distinguish a web application failure from a complete server failure?**
Nagios checks several layers separately:
- **Host check (ping):** is the server itself alive?
- **TCP 8080:** is Tomcat accepting connections?
- **HTTP check:** does `/VehicleRentalManagement/` return **200** and contain the expected text?

| Host (ping) | TCP 8080 | HTTP | Meaning |
|-------------|----------|------|---------|
| UP | OK | CRITICAL (404/500 or text missing) | **Application failure.** Tomcat is running but the app has crashed, failed to deploy or is throwing errors |
| UP | CRITICAL | CRITICAL | **Tomcat is down or hung.** The server is fine |
| **DOWN** | all CRITICAL | all CRITICAL | **Complete server failure** (or a network failure) |

Nagios also uses host dependencies. When the host is DOWN it suppresses the flood of service alerts and reports the root cause, the host itself.

**Q4. What monitoring information would be unavailable if the Nagios server itself stopped?**
Everything Nagios provides stops: no new checks run, so there's no current status for the server, HTTP, Tomcat or MySQL, and the dashboard is unreachable or frozen at its last state. **No alerts or notifications** are sent, so a real outage could go unnoticed (a silent failure). Event handlers don't run, there are no recovery notices, and the history, availability reports and performance graphs have a gap for the downtime. That's why the monitoring server itself should be monitored: a second Nagios instance or an external uptime check, ideally with Nagios in a redundant setup, plus `--restart unless-stopped` on its container.

**Q5. How would you determine whether a failed vehicle availability request is related to Tomcat, MySQL or the network?**
Work through the layers using Nagios's services:
1. **Network:** check the hosts' **PING** service and host state. Packet loss, high latency, or `vehicle-rental-db` showing UNREACHABLE point to the network. Confirm by hand with `check_ping` / `check_tcp` from the Nagios container.
2. **Tomcat:** if the network is fine, look at **Tomcat Port 8080** and the **HTTP** check. Refused connections, timeouts or HTTP 500 point to Tomcat or the app. Inspect it with `docker logs vr-app` (Tomcat's `catalina` log, Java exceptions, OutOfMemoryError) and look at its CPU and memory services.
3. **MySQL:** if Tomcat and HTTP are OK but availability searches still fail, check **MySQL Port 3306**, plus a login check if enabled. Connection refused, slow responses or too many connections point to the database. Inspect it with `docker logs vr-mysql`. Application logs showing `SQLException` / `Communications link failure` confirm it.
4. Use the **alert history** to see which service failed *first*. The first failure is usually the root cause, and the others are side effects.