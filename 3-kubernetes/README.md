# 3. Kubernetes: Container Deployment and Auto Scaling (Minikube)

**Goal:** Run the Vehicle Rental Management app on Minikube as a **Deployment** with 2 replicas, expose it with a **Service**, scale it to 4 replicas, and show that Kubernetes **self-heals** by replacing a deleted pod.

| File | Purpose |
|------|---------|
| [`Dockerfile`](Dockerfile) | Builds the app image (Maven build → Tomcat 9) |
| [`deployment.yaml`](deployment.yaml) | Deployment `vehicle-rental`, 2 replicas, image `vehicle-rental:1.0` |
| [`service.yaml`](service.yaml) | NodePort Service `vehicle-rental-service` on port `30080` |

**Prerequisites:** Docker Desktop running, plus `minikube` and `kubectl` installed. The app URL path is `/VehicleRentalManagement/`.

> **Works in CMD and PowerShell.** Every command is on one line. Copy one line at a time. The "Expected" notes under each block are not commands.

---

## Step 1: Start Minikube and make the image available to the cluster

```
minikube start --driver=docker
minikube status
kubectl get nodes
```

Expected: `host`, `kubelet` and `apiserver` show `Running`, and node `minikube` shows `Ready`.

Get the app source:

```
git clone https://github.com/nikithamoturi/VehicleRentalManagementSystem.git
cd VehicleRentalManagementSystem
```

Copy the [`Dockerfile`](Dockerfile) from this folder into that `VehicleRentalManagementSystem` folder, next to `pom.xml`. Then build the image **inside Minikube**:

```
minikube image build -t vehicle-rental:1.0 .
```

The `.` at the end matters: it means "build from the current folder". The first build takes a few minutes because Maven downloads its dependencies.

If `minikube image build` gives you trouble, build with Docker Desktop and then load the image into Minikube:

```
docker build -t vehicle-rental:1.0 .
minikube image load vehicle-rental:1.0
```

Verify:

```
minikube image ls
```

Expected: the list contains `docker.io/library/vehicle-rental:1.0`. To filter the list, use `minikube image ls | findstr vehicle-rental`, which works in both CMD and PowerShell.

> `imagePullPolicy: IfNotPresent` in `deployment.yaml` matters. Kubernetes uses the image already loaded into Minikube instead of trying to download `vehicle-rental` from Docker Hub, where it doesn't exist (that would cause `ErrImagePull` / `ImagePullBackOff`).

## Step 2: Create the Deployment with 2 replicas

Go back to the folder that holds `deployment.yaml` and `service.yaml` (this `03-kubernetes` folder), then:

```
kubectl apply -f deployment.yaml
kubectl get deployments
kubectl get pods -o wide
kubectl get replicasets
kubectl describe deployment vehicle-rental
```

Expected:
- `deployment.apps/vehicle-rental created`
- `vehicle-rental   2/2   2   2`
- 2 pods with STATUS `Running` and READY `1/1`
- a ReplicaSet with DESIRED `2`

Pods show `0/1 READY` for about 15–20 s while Tomcat starts. The readiness probe waits until `/VehicleRentalManagement/` responds.

## Step 3: Create the Service and open the app

```
kubectl apply -f service.yaml
kubectl get services
kubectl get endpoints vehicle-rental-service
```

Expected: `vehicle-rental-service   NodePort   ...   80:30080/TCP`, and the endpoints list shows both pod IPs on port 8080.

Access the app:

```
minikube service vehicle-rental-service --url
```

Expected: a URL such as `http://127.0.0.1:54321`. On Windows with the Docker driver this command opens a tunnel, so **keep that terminal window open** and run the next commands in a new one.

Open **`<that URL>/VehicleRentalManagement/`** in the browser, e.g. `http://127.0.0.1:54321/VehicleRentalManagement/`. You should see the Vehicle Rental Management System home page, with the login, register and vehicle pages linked.

## Step 4: Scale from 2 to 4 replicas

```
kubectl scale deployment vehicle-rental --replicas=4
kubectl get deployment vehicle-rental
kubectl get pods -o wide
kubectl get endpoints vehicle-rental-service
```

Expected: READY `4/4`. There are 4 pods, 2 old ones and 2 new ones with a younger AGE, and the Service now has 4 pod IPs.

Or declaratively: change `replicas: 2` to `replicas: 4` in `deployment.yaml` and run `kubectl apply -f deployment.yaml`.

### Optional: real auto scaling (HorizontalPodAutoscaler)

```
minikube addons enable metrics-server
kubectl autoscale deployment vehicle-rental --cpu-percent=50 --min=2 --max=6
kubectl get hpa
kubectl top pods
```

Expected: `kubectl get hpa` shows CPU % under TARGETS, and `kubectl top pods` shows live CPU and memory per pod. Metrics take about a minute to appear.

This works because `deployment.yaml` sets CPU `requests`. The HPA computes utilisation against that value.

## Step 5: Delete a pod and watch Kubernetes replace it

```
kubectl get pods
```

Copy one pod name from the list (e.g. `vehicle-rental-6d8f7c9b4-abcde`), then:

```
kubectl delete pod vehicle-rental-6d8f7c9b4-abcde
kubectl get pods -w
```

Replace the name with your real pod name. Press **Ctrl+C** to stop watching.

What you'll see: the deleted pod goes `Terminating`, and a **new pod with a different name** appears almost immediately (`ContainerCreating` → `Running`). The count returns to **4/4**. The ReplicaSet saw `current (3) < desired (4)` and created a replacement.

```
kubectl get deployment vehicle-rental
kubectl describe replicaset -l app=vehicle-rental
```

Expected: the deployment is back to `4/4`, and the **Events** at the bottom of the ReplicaSet description include `Created pod: vehicle-rental-xxxxx` for the replacement.

The app stays reachable through the Service throughout, because the other pods keep serving.

---

## Useful extras (for Q5: rollout and rollback)

Roll out a new version, run from the app folder:

```
minikube image build -t vehicle-rental:2.0 .
kubectl set image deployment/vehicle-rental vehicle-rental=vehicle-rental:2.0
kubectl rollout status deployment/vehicle-rental
kubectl rollout history deployment/vehicle-rental
```

If something broke, go back to the previous version, or to a specific revision:

```
kubectl rollout undo deployment/vehicle-rental
kubectl rollout undo deployment/vehicle-rental --to-revision=1
```

Debugging a bad pod:

```
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

`describe` shows Events such as `ImagePullBackOff`, probe failures and `OOMKilled`. `logs` shows the Tomcat and application output.

### Common errors

| Error | Fix |
|-------|-----|
| `ErrImagePull` / `ImagePullBackOff` | The image isn't inside Minikube. Run `minikube image build -t vehicle-rental:1.0 .` (or `docker build` plus `minikube image load`) and check `minikube image ls` |
| Pods stuck at `0/1 READY` | Tomcat is still starting. Wait 30 s, then check `kubectl logs <pod-name>` |
| Browser can't open the URL | Keep the `minikube service ... --url` window open, and add `/VehicleRentalManagement/` to the end of the URL |
| `minikube start` fails | Make sure Docker Desktop is running first |

### Cleanup

```
kubectl delete -f service.yaml -f deployment.yaml
minikube stop
```

---

## Scenario-based Questions

**Q1. How does Kubernetes help keep the rental portal available when an application pod terminates?**
The Deployment creates a **ReplicaSet** that keeps the declared number of pods running. Its controller continuously compares the *desired* state (e.g. 4 replicas) with the *actual* state. When a pod crashes, is deleted, or its node fails, the actual count drops, and Kubernetes immediately schedules a **replacement pod**. Meanwhile the **Service** routes customers only to the remaining healthy pods. The readiness probe stops traffic to pods that aren't ready, and the liveness probe restarts containers that hang. Customers keep using the portal with no visible outage. This is shown in Step 5.

**Q2. What is the purpose of specifying a replica count in a Deployment?**
`replicas` declares how many identical copies of the application pod must run at all times. It provides:
- **High availability:** if one pod fails, others keep serving
- **Load distribution:** the Service spreads customer requests across all replicas
- **Self-healing target:** the ReplicaSet always restores this exact number
- **Easy scaling:** change the number with `kubectl scale` or in the YAML, and Kubernetes adds or removes pods to match

**Q3. Why may the company need to scale the rental portal during holiday seasons?**
During holidays and weekends many more customers search for vehicles and submit rental requests at the same time. With only 2 pods, CPU and memory saturate, responses slow down, requests time out and bookings, and so revenue, are lost. Scaling to 4 or more replicas adds capacity so the load is shared and response times stay low. After the peak the deployment can be scaled back down to save resources and cost. A **HorizontalPodAutoscaler** does this automatically based on CPU usage (`kubectl autoscale ... --min=2 --max=6 --cpu-percent=50`).

**Q4. How does a Service provide a stable access point when pod IP addresses change?**
Pods are temporary: every replacement or new replica gets a new IP address. A **Service** gets a fixed **ClusterIP** and a DNS name (`vehicle-rental-service`), and for NodePort also a fixed node port (`30080`), which never change. It doesn't point at IPs directly. It uses a **label selector** (`app: vehicle-rental`), and Kubernetes keeps its **Endpoints** list updated with the IPs of all ready pods matching that label. Clients always use the same Service address, and kube-proxy load-balances each request to one of the current pods, whatever their IPs are now. This is visible with `kubectl get endpoints`.

**Q5. What steps can be taken if the latest application image introduces an error after deployment?**
1. **Detect:** `kubectl rollout status`, `kubectl get pods` (look for `CrashLoopBackOff`, `ImagePullBackOff`, `0/1 READY`), `kubectl describe pod` and `kubectl logs <pod>`.
2. **Limit the damage:** a RollingUpdate with readiness probes doesn't replace old healthy pods until new ones become ready, so a badly broken image often stalls without taking the site down. `kubectl rollout pause deployment/vehicle-rental` stops further rollout.
3. **Roll back:** `kubectl rollout undo deployment/vehicle-rental` (or `--to-revision=N` from `kubectl rollout history`). Alternatively `kubectl set image deployment/vehicle-rental vehicle-rental=vehicle-rental:1.0` to the last known good tag.
4. **Verify:** `kubectl rollout status` and open the app through the Service.
5. **Fix and redeploy:** fix the bug, build and test a new image with a **new version tag** (never overwrite tags or rely on `latest`), then roll it out again. Ideally test in CI/staging first.