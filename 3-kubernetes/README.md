# 3. Kubernetes: Container Deployment and Auto Scaling (Minikube)

**Goal:** Run the Vehicle Rental Management app on Minikube as a **Deployment** with 2 replicas, expose it with a **Service**, scale it to 4 replicas, and show that Kubernetes **self-heals** by replacing a deleted pod.

| File | Purpose |
|------|---------|
| [`Dockerfile`](Dockerfile) | Builds the app image (Maven build → Tomcat 9) |
| [`deployment.yaml`](deployment.yaml) | Deployment `vehicle-rental`, 2 replicas, image `vehicle-rental:1.0` |
| [`service.yaml`](service.yaml) | NodePort Service `vehicle-rental-service` on port `30080` |

**Prerequisites:** Docker, `minikube` and `kubectl` installed. The app URL path is `/VehicleRentalManagement/`.

---

## Step 1: Start Minikube and make the image available to the cluster

```bash
minikube start --driver=docker
minikube status                 # host, kubelet, apiserver: Running
kubectl get nodes               # minikube   Ready   control-plane
```

Get the app source and add the Dockerfile:

```bash
git clone https://github.com/nikithamoturi/VehicleRentalManagementSystem.git
cd VehicleRentalManagementSystem
# copy Dockerfile from this folder into the repo root (next to pom.xml)
```

Build the image **inside Minikube**. Pick any one option:

```bash
# Option A (simplest): build directly in Minikube's image store
minikube image build -t vehicle-rental:1.0 .

# Option B: build with Docker on your machine, then load it into Minikube
docker build -t vehicle-rental:1.0 .
minikube image load vehicle-rental:1.0

# Option C: point your Docker CLI at Minikube's Docker daemon, then build
eval $(minikube docker-env)                                          # Linux/macOS
# & minikube -p minikube docker-env --shell powershell | Invoke-Expression   # Windows PowerShell
docker build -t vehicle-rental:1.0 .
```

Verify:

```bash
minikube image ls | grep vehicle-rental      # docker.io/library/vehicle-rental:1.0
```

> `imagePullPolicy: IfNotPresent` in `deployment.yaml` matters. Kubernetes uses the image already loaded into Minikube instead of trying to download `vehicle-rental` from Docker Hub, where it doesn't exist (that would cause `ErrImagePull` / `ImagePullBackOff`).

## Step 2: Create the Deployment with 2 replicas

```bash
kubectl apply -f deployment.yaml
kubectl get deployments          # vehicle-rental   2/2   2   2
kubectl get pods -o wide         # 2 pods, STATUS Running, READY 1/1
kubectl get replicasets          # ReplicaSet created by the Deployment, DESIRED 2
kubectl describe deployment vehicle-rental
```

Pods show `0/1 READY` for about 15–20 s while Tomcat starts. The readiness probe waits until `/VehicleRentalManagement/` responds.

## Step 3: Create the Service and open the app

```bash
kubectl apply -f service.yaml
kubectl get services             # vehicle-rental-service   NodePort   ...   80:30080/TCP
kubectl get endpoints vehicle-rental-service    # lists both pod IPs:8080
```

Access the app:

```bash
minikube service vehicle-rental-service --url
# e.g. http://192.168.49.2:30080   (on Windows/macOS with the Docker driver you get
#  a 127.0.0.1:<port> tunnel URL; keep that terminal open)
```

Open **`<that URL>/VehicleRentalManagement/`** in the browser. You should see the Vehicle Rental Management System home page, with the login, register and vehicle pages linked.

From the command line:

```bash
curl -s $(minikube service vehicle-rental-service --url)/VehicleRentalManagement/ | grep -i "<title>"
```

## Step 4: Scale from 2 to 4 replicas

```bash
kubectl scale deployment vehicle-rental --replicas=4
kubectl get deployment vehicle-rental     # READY 4/4
kubectl get pods -o wide                  # 4 pods: 2 old + 2 new (younger AGE)
kubectl get endpoints vehicle-rental-service   # now 4 pod IPs behind the Service
```

Or declaratively: change `replicas: 2` to `replicas: 4` in `deployment.yaml` and run `kubectl apply -f deployment.yaml`.

### Optional: real auto scaling (HorizontalPodAutoscaler)

```bash
minikube addons enable metrics-server
kubectl autoscale deployment vehicle-rental --cpu-percent=50 --min=2 --max=6
kubectl get hpa                           # TARGETS shows CPU %, REPLICAS adjusts automatically
kubectl top pods                          # live CPU/memory per pod
```

This works because `deployment.yaml` sets CPU `requests`. The HPA computes utilisation against that value.

## Step 5: Delete a pod and watch Kubernetes replace it

```bash
kubectl get pods                                  # note one pod name
kubectl delete pod <one-of-the-pod-names>
kubectl get pods -w                               # watch live (Ctrl+C to stop)
```

What you'll see: the deleted pod goes `Terminating`, and a **new pod with a different name** appears almost immediately (`ContainerCreating` → `Running`). The count returns to **4/4**. The ReplicaSet saw `current (3) < desired (4)` and created a replacement.

```bash
kubectl get deployment vehicle-rental            # back to 4/4
kubectl describe replicaset -l app=vehicle-rental | tail -10   # Events: "Created pod: vehicle-rental-xxxxx"
```

The app stays reachable through the Service throughout, because the other pods keep serving.

---

## Useful extras (for Q5: rollout and rollback)

```bash
# Roll out a new version
minikube image build -t vehicle-rental:2.0 .
kubectl set image deployment/vehicle-rental vehicle-rental=vehicle-rental:2.0
kubectl rollout status deployment/vehicle-rental
kubectl rollout history deployment/vehicle-rental

# Something broke -> go back
kubectl rollout undo deployment/vehicle-rental                 # previous version
kubectl rollout undo deployment/vehicle-rental --to-revision=1 # specific version

# Debugging a bad pod
kubectl describe pod <pod>      # Events: ImagePullBackOff, probe failures, OOMKilled...
kubectl logs <pod>              # Tomcat / application logs
```

### Cleanup

```bash
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