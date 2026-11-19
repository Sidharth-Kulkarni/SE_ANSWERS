# Dockerfile for the Vehicle Rental Management System
# Place this file in the ROOT of the VehicleRentalManagementSystem repo (next to pom.xml).
# Multi-stage build: no local Maven/JDK needed, Docker builds the WAR itself.

# ---- Stage 1: build the WAR with Maven ----
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -B dependency:go-offline
COPY src ./src
RUN mvn -B clean package -DskipTests

# ---- Stage 2: run on Tomcat 9 (app uses javax.servlet, so NOT Tomcat 10) ----
FROM tomcat:9.0-jdk17
RUN rm -rf /usr/local/tomcat/webapps/*
COPY --from=build /app/target/VehicleRentalManagement.war /usr/local/tomcat/webapps/VehicleRentalManagement.war
EXPOSE 8080
CMD ["catalina.sh", "run"]