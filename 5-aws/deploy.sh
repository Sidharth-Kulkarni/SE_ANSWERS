#!/bin/bash
# deploy.sh - run ON THE EC2 INSTANCE (Ubuntu Server 22.04 LTS) after you SSH in.
# Installs Java 17, Maven, Git and Tomcat 9, builds the Vehicle Rental app
# and deploys it to Tomcat.
#
# Usage on EC2:
#   nano deploy.sh   (paste this file, save with Ctrl+O, Enter, Ctrl+X)
#   bash deploy.sh
set -e

REPO_URL="https://github.com/nikithamoturi/VehicleRentalManagementSystem.git"
APP_DIR="$HOME/VehicleRentalManagementSystem"
WAR_NAME="VehicleRentalManagement.war"
WEBAPPS="/var/lib/tomcat9/webapps"

echo "=== 1. Updating packages ==="
sudo apt update -y

echo "=== 2. Installing Java 17, Maven, Git, Tomcat 9 ==="
sudo apt install -y openjdk-17-jdk maven git tomcat9 tomcat9-admin
java -version
mvn -version

echo "=== 3. Starting Tomcat and enabling it on boot ==="
sudo systemctl enable tomcat9
sudo systemctl start tomcat9

echo "=== 4. Getting the source code ==="
if [ -d "$APP_DIR/.git" ]; then
  git -C "$APP_DIR" pull
else
  git clone "$REPO_URL" "$APP_DIR"
fi

echo "=== 5. Building the WAR with Maven ==="
cd "$APP_DIR"
mvn -B clean package
ls -lh "target/$WAR_NAME"

echo "=== 6. Deploying to Tomcat ==="
sudo rm -rf "$WEBAPPS/VehicleRentalManagement" "$WEBAPPS/$WAR_NAME"
sudo cp "target/$WAR_NAME" "$WEBAPPS/"
sudo chown tomcat:tomcat "$WEBAPPS/$WAR_NAME"

echo "Waiting for Tomcat to unpack the WAR..."
for i in $(seq 1 30); do
  if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/VehicleRentalManagement/" | grep -q 200; then
    break
  fi
  sleep 2
done

echo "=== 7. Verifying ==="
sudo systemctl --no-pager status tomcat9 | head -5
curl -s -o /dev/null -w "App HTTP status: %{http_code}\n" "http://localhost:8080/VehicleRentalManagement/"

PUBLIC_IP=$(curl -s --max-time 3 https://checkip.amazonaws.com || echo "<EC2-public-IP>")
echo
echo "Done. Open in your browser: http://${PUBLIC_IP}:8080/VehicleRentalManagement/"