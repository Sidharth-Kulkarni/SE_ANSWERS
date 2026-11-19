# 5. AWS: Cloud Deployment using EC2

**Goal:** Launch an **Ubuntu EC2 instance**, deploy the Vehicle Rental Management System on **Tomcat 9**, and give customers browser access through a correctly configured **security group**.

| Setting | Value |
|---------|-------|
| Region | Asia Pacific (Mumbai) `ap-south-1`, or any region |
| Instance name | `vehicle-rental-server` |
| AMI | **Ubuntu Server 22.04 LTS** (free tier eligible) |
| Instance type | `t2.micro` or `t3.micro` (free tier) |
| Key pair | `vr-key` (RSA, `.pem`) |
| Security group | `vehicle-rental-sg`: SSH 22 from **My IP**, TCP 8080 from **Anywhere** |
| App URL | `http://<EC2-public-IP>:8080/VehicleRentalManagement/` |

> **Why 22.04 and not 24.04?** The app uses `javax.servlet`, so it needs **Tomcat 9**. Ubuntu 22.04 has Tomcat 9 in `apt` (`tomcat9`), while 24.04 only offers Tomcat 10. For 24.04, see the Docker option in Step 4.

> **Where to run what:** commands in boxes labelled **Windows (CMD / PowerShell)** run on your PC. Commands labelled **EC2 (Ubuntu)** run in the SSH session on the server, which is Linux.

---

## Step 1: Launch the Ubuntu EC2 instance

1. Log in to the **AWS Console** → search **EC2** → **Instances** → **Launch instances**.
2. **Name:** `vehicle-rental-server`
3. **Application and OS Images:** **Ubuntu** → **Ubuntu Server 22.04 LTS (HVM), SSD Volume Type**, 64-bit (x86)
4. **Instance type:** `t2.micro` (or `t3.micro`, whichever is marked *Free tier eligible*)
5. **Key pair (login):** **Create new key pair** → name `vr-key` → type **RSA** → format **.pem** → **Create**. The file `vr-key.pem` downloads. **Keep it safe; you can't download it again.**
6. **Network settings** → **Edit**:
   - Auto-assign public IP: **Enable**
   - **Create security group**, name `vehicle-rental-sg`
   - Rule 1: Type **SSH**, Port **22**, Source **My IP**
   - **Add security group rule** → Rule 2: Type **Custom TCP**, Port **8080**, Source **Anywhere (0.0.0.0/0)**
7. **Configure storage:** 8 GiB gp3 (default) is enough.
8. **Launch instance** → **View all instances**.

Wait until **Instance state = Running** and **Status checks = 2/2 checks passed**. Select the instance and copy its **Public IPv4 address** (e.g. `13.233.45.67`).

## Step 2: Connect to the instance with SSH

Windows 10/11 has `ssh` built in. Open CMD **in the folder that holds `vr-key.pem`** (e.g. `Downloads`).

First, lock down the key file's permissions. Otherwise SSH refuses it with `UNPROTECTED PRIVATE KEY FILE`.

**Windows (CMD):**
```
icacls vr-key.pem /inheritance:r
icacls vr-key.pem /grant:r "%USERNAME%":R
```

**Windows (PowerShell)**, if you're using PowerShell instead of CMD:
```
icacls vr-key.pem /inheritance:r
icacls vr-key.pem /grant:r "$($env:USERNAME):R"
```

Connect. Replace the IP with your instance's public IP, and type `yes` the first time:

**Windows (CMD / PowerShell):**
```
ssh -i vr-key.pem ubuntu@13.233.45.67
```

Expected: the prompt changes to `ubuntu@ip-172-31-xx-xx:~$`. You're now on the EC2 server.

> **Alternative without SSH:** EC2 console → select the instance → **Connect** → **EC2 Instance Connect** → **Connect** opens a terminal in the browser. This needs port 22 open to AWS's Instance Connect service. If your SSH rule is "My IP" only and this fails, temporarily add a rule for 22 from Anywhere, then remove it afterwards.

## Step 3: Install Java, Maven, Git and Tomcat 9

**EC2 (Ubuntu):**
```
sudo apt update -y
sudo apt install -y openjdk-17-jdk maven git tomcat9 tomcat9-admin
java -version
mvn -version
sudo systemctl enable tomcat9
sudo systemctl start tomcat9
sudo systemctl status tomcat9 --no-pager
```

Expected: `openjdk version "17..."`, `Apache Maven 3.6.3`, and Tomcat shown as `active (running)`.

Test Tomcat from your PC's browser: **http://13.233.45.67:8080** should show the Tomcat **"It works!"** page. If it doesn't load, the **8080 security group rule** is missing (see Q1).

## Step 4: Build and deploy the Vehicle Rental app

**EC2 (Ubuntu):**
```
git clone https://github.com/nikithamoturi/VehicleRentalManagementSystem.git
cd VehicleRentalManagementSystem
mvn -B clean package
ls -lh target/VehicleRentalManagement.war
sudo cp target/VehicleRentalManagement.war /var/lib/tomcat9/webapps/
ls /var/lib/tomcat9/webapps/
```

Expected: `BUILD SUCCESS`, then after a few seconds `/var/lib/tomcat9/webapps/` contains both `VehicleRentalManagement.war` and an unpacked `VehicleRentalManagement` folder. Tomcat auto-deploys any WAR copied there.

> **One-command option:** [`deploy.sh`](deploy.sh) does Steps 3 and 4 in one go. On EC2, run `nano deploy.sh`, paste the file's contents, save (Ctrl+O, Enter, Ctrl+X), then run `bash deploy.sh`.

**Option: copy a WAR from your PC instead of building on EC2.** This is useful if you already have the WAR from Jenkins (Task 2). Run it from the folder with the key and the WAR:

**Windows (CMD / PowerShell):**
```
scp -i vr-key.pem VehicleRentalManagement.war ubuntu@13.233.45.67:/home/ubuntu/
```

Then on **EC2 (Ubuntu):**
```
sudo cp /home/ubuntu/VehicleRentalManagement.war /var/lib/tomcat9/webapps/
```

**Option for Ubuntu 24.04 (no `tomcat9` package): run Tomcat in Docker.** Use the `Dockerfile` from `03-kubernetes`. Copy it to the server with `scp` like above, into the cloned repo folder.

**EC2 (Ubuntu):**
```
sudo apt install -y docker.io git
git clone https://github.com/nikithamoturi/VehicleRentalManagementSystem.git
cd VehicleRentalManagementSystem
sudo docker build -t vehicle-rental:1.0 .
sudo docker run -d --name vr-app -p 8080:8080 --restart unless-stopped vehicle-rental:1.0
```

## Step 5: Open the portal and verify

From any browser, open:

**`http://13.233.45.67:8080/VehicleRentalManagement/`**

Expected: the **Vehicle Rental Management System** home page, with working links to Login, Register and Vehicles.

Verify on the server:

**EC2 (Ubuntu):**
```
sudo systemctl status tomcat9 --no-pager
curl -I http://localhost:8080/VehicleRentalManagement/
sudo journalctl -u tomcat9 --no-pager -n 30
sudo ls /var/log/tomcat9/
```

Expected: `active (running)`, `HTTP/1.1 200`, and log lines like `Deployment of web application archive [.../VehicleRentalManagement.war] has finished`.

### Optional: serve on port 80 (no `:8080` in the URL)

**EC2 (Ubuntu):**
```
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
```

Then add an inbound rule **HTTP, port 80, Anywhere** to `vehicle-rental-sg`, and open `http://13.233.45.67/VehicleRentalManagement/`. This rule is lost on reboot unless you save it with `iptables-persistent`.

### Important notes

- **The public IP changes** every time you stop and start the instance. Allocate an **Elastic IP** (EC2 → Elastic IPs → Allocate → Associate with the instance) if you need a fixed address.
- **Avoid charges:** after the lab, **Terminate** the instance (Instance state → Terminate). Release any Elastic IP you allocated, because an unattached Elastic IP is billed.

### Common errors

| Problem | Fix |
|---------|-----|
| `UNPROTECTED PRIVATE KEY FILE` / `Permission denied (publickey)` | Run the `icacls` commands from Step 2. Log in as `ubuntu`, not root, and use the right `.pem` |
| `ssh: connect to host ... Connection timed out` | The SSH rule is missing, your IP changed (edit the rule → My IP again), or the instance is stopped |
| Browser times out on `:8080` | Add the inbound **Custom TCP 8080 from 0.0.0.0/0** rule. Make sure you use the **public** IP and `http://`, not `https://` |
| Tomcat page works but `/VehicleRentalManagement/` gives 404 | The WAR isn't deployed yet or the name is wrong. Check `ls /var/lib/tomcat9/webapps/` and the logs |
| `E: Unable to locate package tomcat9` | You're on Ubuntu 24.04. Use the Docker option in Step 4, or launch a 22.04 instance |

---

## Scenario-based Questions

**Q1. Which EC2 or security group configuration issues could prevent customers from opening the rental portal?**
- **No inbound rule for the app port:** security groups deny all inbound traffic by default, so without **TCP 8080** (or 80/443) open to `0.0.0.0/0` the browser times out.
- The rule's **source is too narrow**, e.g. 8080 allowed only from "My IP", so it works for the admin but not for customers.
- **Wrong port**: e.g. port 80 opened while Tomcat listens on 8080, or the other way round.
- **No public IP** (auto-assign disabled), an instance in a **private subnet**, or no **Internet Gateway / route** to `0.0.0.0/0` in the VPC route table.
- A **Network ACL** on the subnet blocking inbound 8080, or the return (ephemeral 1024–65535) traffic.
- The instance is **stopped**, or its **public IP changed** after a restart and customers use the old address (no Elastic IP).
- An OS firewall (`ufw`) on the instance blocking 8080, or Tomcat not running or listening only on localhost.
- Customers using `https://` when only HTTP is configured.

**Q2. Why should the company allow SSH access only from trusted administrative addresses?**
SSH (port 22) gives **full command-line control** of the server. Anyone who gets in can steal customer and rental data, change the application, install malware or delete everything. Port 22 open to `0.0.0.0/0` is scanned constantly by bots trying brute-force logins and known exploits. Restricting the source to the admins' IPs (e.g. "My IP", the office IP range or a VPN) reduces the **attack surface**, so attackers can't even reach the login prompt. This is the **principle of least privilege**. It's combined with key-based login only (no passwords), protecting the `.pem` key, and options like a bastion host or **AWS Systems Manager Session Manager**, which needs no open port 22 at all.

**Q3. What would customers observe if Tomcat stops while the EC2 instance continues to run?**
The server is up, but nothing is listening on port 8080. The browser shows **"This site can't be reached / ERR_CONNECTION_REFUSED"** almost immediately. It isn't a slow timeout, because the instance actively refuses the connection, and customers can't search vehicles or submit rentals. Meanwhile the EC2 console still shows the instance as **Running** with **2/2 status checks passed**, because EC2 checks only the VM, not the application. That's why application-level monitoring is needed: an HTTP health check (like the Nagios check in Task 4) or a load balancer health check. On the server, `sudo systemctl status tomcat9` shows `inactive/failed`, and `sudo systemctl restart tomcat9` restores service. `systemctl enable` makes it start on boot.

**Q4. How could the company handle an increase in customer requests during holiday periods?**
- **Vertical scaling:** stop the instance, change it to a bigger type (e.g. `t3.micro` → `t3.large` / `m5.large`), then start it. This is simple but needs brief downtime and has an upper limit.
- **Horizontal scaling (better):** create an **AMI** of the configured server and a **Launch Template**, then an **Auto Scaling Group** across multiple Availability Zones with an **Application Load Balancer** in front. Scaling policies add instances when, for example, average **CPU > 70 %** or request count is high, and remove them when the load drops. **Scheduled scaling** can add capacity in advance for known holiday dates.
- **Move the database to Amazon RDS** (managed MySQL with read replicas), so the app servers stay stateless and easy to scale.
- **Caching / CDN:** use **CloudFront** for static content and **ElastiCache** for frequently read data such as the vehicle list.
- Monitor with **CloudWatch** metrics and alarms to see when to scale.

**Q5. Why might multiple EC2 instances behind a load balancer be preferred for a customer-facing rental portal?**
- **High availability:** if one instance or Tomcat fails, the load balancer's **health checks** detect it and stop sending traffic there, so customers are served by the healthy instances with no outage. Spreading instances across **multiple Availability Zones** also survives a data-centre failure.
- **Load distribution and performance:** requests are shared across instances, so no single server is overloaded during peaks.
- **Scalability:** an Auto Scaling Group can add or remove instances behind the same load balancer automatically, without customers noticing.
- **Zero-downtime maintenance:** instances can be updated one at a time (rolling deployment) while the others keep serving.
- **A single stable endpoint:** customers use one DNS name (the load balancer, or a Route 53 domain) even as instances change. The load balancer can also handle **HTTPS/SSL** certificates via ACM, and instances can stay in private subnets for better security.
- A single instance is a **single point of failure**: any crash, reboot or overload takes the whole portal down.