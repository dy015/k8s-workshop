# Kubernetes Troubleshooting Workshop - Solutions Guide

**Workshop Duration:** 4-6 hours  
**Target Audience:** Kubernetes Admins, DevOps Engineers, SREs  
**Difficulty:** Beginner to Advanced  

---

## Table of Contents

1. [Workshop Setup](#workshop-setup)
2. [Scenario 1: Pod CrashLoopBackOff & ImagePullBackOff](#scenario-1)
3. [Scenario 2: Service Discovery & Networking](#scenario-2)
4. [Scenario 3: Storage & StatefulSets](#scenario-3)
5. [Scenario 4: ConfigMap, Secrets & Resources](#scenario-4)
6. [Scenario 5: RBAC, Security & Node Issues](#scenario-5)
7. [Quick Reference Commands](#quick-reference)

---

## Workshop Setup

### Prerequisites
- Kubernetes cluster installed (use k8s-manager-final.sh)
- kubectl configured
- Basic understanding of Kubernetes concepts

### Deploy the Application
```bash
chmod +x workshop-scripts/*.sh
bash workshop-scripts/00-deploy-app.sh
```

### Verify Deployment
```bash
kubectl get all -n workshop-app
kubectl get pods -n workshop-app -o wide
```

### Architecture Overview
```
┌─────────────┐
│   Frontend  │ (nginx, NodePort 30080)
│   2 replicas│
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Backend   │ (API, 3 replicas, HPA enabled)
│  ClusterIP  │
└──────┬──────┘
       │
       ├────────────┐
       ▼            ▼
┌──────────┐  ┌──────────┐
│  MySQL   │  │  Redis   │
│StatefulSet│  │Deployment│
└──────────┘  └──────────┘
```

---

## Scenario 1: Pod CrashLoopBackOff & ImagePullBackOff {#scenario-1}

### Concepts Covered
- Pod lifecycle and states
- Container image management
- Resource limits and OOMKilled
- Pod events and logs
- Restart policies

### Activate Scenario
```bash
bash workshop-scripts/01-break-pods.sh
```

### Issue 1a: ImagePullBackOff

**Symptoms:**
```bash
$ kubectl get pods -n workshop-app
NAME                            READY   STATUS             RESTARTS   AGE
broken-image-xxx                0/1     ImagePullBackOff   0          2m
```

**Diagnosis:**
```bash
# Check pod status
kubectl describe pod broken-image-xxx -n workshop-app

# Look for events section:
# Failed to pull image "nonexistent/fake-image:v99.99.99": 
# rpc error: code = Unknown desc = Error response from daemon: 
# pull access denied for nonexistent/fake-image
```

**Root Cause:**
- Image does not exist in the registry
- Image name is misspelled
- Private registry credentials missing

**Solution Steps:**

1. **Identify the correct image:**
```bash
# Check the deployment
kubectl get deployment broken-image -n workshop-app -o yaml | grep image:
```

2. **Fix the image:**
```bash
# Option A: Patch the deployment
kubectl set image deployment/broken-image \
  app=nginx:alpine \
  -n workshop-app

# Option B: Edit directly
kubectl edit deployment broken-image -n workshop-app
# Change image to: nginx:alpine
```

3. **Verify fix:**
```bash
kubectl get pods -n workshop-app | grep broken-image
kubectl rollout status deployment/broken-image -n workshop-app
```

**Prevention:**
- Use image digests for production
- Implement image validation in CI/CD
- Use private registries with proper authentication
- Tag images with semantic versions

---

### Issue 1b: CrashLoopBackOff

**Symptoms:**
```bash
$ kubectl get pods -n workshop-app
NAME                          READY   STATUS             RESTARTS   AGE
crash-loop-xxx                0/1     CrashLoopBackOff   5          3m
```

**Diagnosis:**
```bash
# Check pod logs
kubectl logs crash-loop-xxx -n workshop-app

# Check previous container logs (after crash)
kubectl logs crash-loop-xxx -n workshop-app --previous

# Describe pod for restart count
kubectl describe pod crash-loop-xxx -n workshop-app
```

**Root Cause:**
Container is configured to exit with code 1 immediately:
```yaml
command: ["/bin/sh"]
args: ["-c", "exit 1"]
```

**Solution Steps:**

1. **Check the deployment spec:**
```bash
kubectl get deployment crash-loop -n workshop-app -o yaml
```

2. **Fix the command:**
```bash
# Patch with a proper command
kubectl patch deployment crash-loop -n workshop-app --type json \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/command", "value": ["/bin/sh"]},
       {"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": ["-c", "sleep infinity"]}]'
```

3. **Verify:**
```bash
kubectl get pods -n workshop-app | grep crash-loop
kubectl logs crash-loop-xxx -n workshop-app
```

**Common Causes of CrashLoopBackOff:**
- Application configuration errors
- Missing dependencies
- Failed health checks
- Database connection issues
- Incorrect entrypoint/command

---

### Issue 1c: OOMKilled

**Symptoms:**
```bash
$ kubectl get pods -n workshop-app
NAME                          READY   STATUS      RESTARTS   AGE
oom-killed-xxx                0/1     OOMKilled   3          2m
```

**Diagnosis:**
```bash
# Check pod status
kubectl describe pod oom-killed-xxx -n workshop-app

# Look for:
# State:          Terminated
# Reason:         OOMKilled
# Exit Code:      137
```

**Root Cause:**
Memory limit set too low (10Mi) for nginx:
```yaml
resources:
  limits:
    memory: "10Mi"  # Too low for nginx!
```

**Solution Steps:**

1. **Check current limits:**
```bash
kubectl get pod oom-killed-xxx -n workshop-app -o yaml | grep -A 5 resources:
```

2. **Fix memory limits:**
```bash
# Update deployment with appropriate limits
kubectl patch deployment oom-killed -n workshop-app -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "app",
          "resources": {
            "requests": {
              "memory": "64Mi"
            },
            "limits": {
              "memory": "128Mi"
            }
          }
        }]
      }
    }
  }
}'
```

3. **Monitor memory usage:**
```bash
# Wait for pod to be running
kubectl wait --for=condition=ready pod -l app=oom-killed -n workshop-app --timeout=60s

# Check actual memory usage
kubectl top pod -l app=oom-killed -n workshop-app
```

**Best Practices:**
- Set realistic memory limits based on application needs
- Use vertical pod autoscaler (VPA) for recommendations
- Monitor memory usage in production
- Set requests = limits for guaranteed QoS

**Cleanup Scenario 1:**
```bash
kubectl delete deployment broken-image crash-loop oom-killed -n workshop-app
```

---

## Scenario 2: Service Discovery & Networking {#scenario-2}

### Concepts Covered
- Kubernetes Services (ClusterIP, NodePort)
- Service selectors and endpoints
- CoreDNS and DNS resolution
- NetworkPolicies
- Service mesh basics

### Activate Scenario
```bash
bash workshop-scripts/02-break-networking.sh
```

### Issue 2a: Service Selector Mismatch

**Symptoms:**
```bash
# Frontend can't reach backend
$ kubectl exec -it <frontend-pod> -n workshop-app -- curl backend:3000
curl: (6) Could not resolve host: backend
```

**Diagnosis:**
```bash
# Check service
kubectl get svc backend -n workshop-app

# Check endpoints - should show no endpoints!
kubectl get endpoints backend -n workshop-app
NAME      ENDPOINTS   AGE
backend   <none>      5m

# Check service selector
kubectl get svc backend -n workshop-app -o yaml | grep -A 3 selector:

# Check pod labels
kubectl get pods -n workshop-app --show-labels | grep backend
```

**Root Cause:**
Service selector was changed to "wrong-label" but pods have "app: backend"

**Solution Steps:**

1. **Compare labels:**
```bash
# Service selector
kubectl get svc backend -n workshop-app -o jsonpath='{.spec.selector}'

# Pod labels
kubectl get pods -l app=backend -n workshop-app --show-labels
```

2. **Fix the selector:**
```bash
# Restore correct selector
kubectl patch service backend -n workshop-app -p '{
  "spec": {
    "selector": {
      "app": "backend"
    }
  }
}'
```

3. **Verify endpoints are created:**
```bash
kubectl get endpoints backend -n workshop-app
# Should now show IP addresses

# Test connectivity
kubectl exec -it <frontend-pod> -n workshop-app -- curl backend:3000
```

**Key Learning:**
- Services use selectors to match pods
- Endpoints are automatically created when selectors match
- No endpoints = no service traffic routing

---

### Issue 2b: Wrong Service Ports

**Symptoms:**
```bash
# Service exists but connection refused
$ kubectl exec -it <pod> -n workshop-app -- curl broken-service:9999
curl: (7) Failed to connect to broken-service port 9999: Connection refused
```

**Diagnosis:**
```bash
# Check service definition
kubectl get svc broken-service -n workshop-app -o yaml

# Compare with pod ports
kubectl get pod <backend-pod> -n workshop-app -o yaml | grep -A 5 ports:
```

**Root Cause:**
- Service port: 9999
- Service targetPort: 8888
- Actual container port: 3000

**Solution Steps:**

1. **Fix service ports:**
```bash
kubectl patch svc broken-service -n workshop-app -p '{
  "spec": {
    "ports": [{
      "port": 3000,
      "targetPort": 3000
    }]
  }
}'
```

2. **Test:**
```bash
kubectl exec -it <pod> -n workshop-app -- curl broken-service:3000
```

**Cleanup:**
```bash
kubectl delete svc broken-service -n workshop-app
```

---

### Issue 2c: CoreDNS Misconfiguration

**Symptoms:**
```bash
# DNS resolution fails cluster-wide
$ kubectl exec -it <pod> -n workshop-app -- nslookup kubernetes.default
Server:    10.96.0.10
Address 1: 10.96.0.10

nslookup: can't resolve 'kubernetes.default'
```

**Diagnosis:**
```bash
# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns

# Check CoreDNS config
kubectl get configmap coredns -n kube-system -o yaml
```

**Root Cause:**
CoreDNS Corefile was modified to forward to invalid DNS server (1.2.3.4)

**Solution Steps:**

1. **Restore CoreDNS config:**
```bash
# If backup exists
kubectl apply -f /tmp/coredns-backup.yaml

# Or restore default config
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
EOF
```

2. **Restart CoreDNS:**
```bash
kubectl rollout restart deployment coredns -n kube-system
kubectl rollout status deployment coredns -n kube-system
```

3. **Verify DNS works:**
```bash
# Test from a pod
kubectl run test-dns --image=busybox:latest --rm -it --restart=Never -- nslookup kubernetes.default

# Should resolve successfully
```

**DNS Troubleshooting Tips:**
- Always test DNS from within pods, not from nodes
- Check /etc/resolv.conf in pods
- Verify CoreDNS pods are running
- Check CoreDNS service exists and has endpoints

---

### Issue 2d: Overly Restrictive NetworkPolicy

**Symptoms:**
```bash
# All pods in namespace can't communicate
$ kubectl exec -it <frontend-pod> -n workshop-app -- curl backend:3000
# Hangs and times out
```

**Diagnosis:**
```bash
# Check network policies
kubectl get networkpolicy -n workshop-app

# Describe the policy
kubectl describe networkpolicy deny-all -n workshop-app
```

**Root Cause:**
NetworkPolicy that denies all ingress and egress traffic:
```yaml
spec:
  podSelector: {}  # Applies to all pods
  policyTypes:
  - Ingress
  - Egress
  # No rules = deny all
```

**Solution Steps:**

1. **Option A - Delete restrictive policy:**
```bash
kubectl delete networkpolicy deny-all -n workshop-app
```

2. **Option B - Create proper allow policy:**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app-traffic
  namespace: workshop-app
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}  # Allow all ingress
  egress:
  - {}  # Allow all egress
EOF
```

3. **Test connectivity:**
```bash
kubectl exec -it <frontend-pod> -n workshop-app -- curl backend:3000
```

**NetworkPolicy Best Practices:**
- Start with default deny, then explicitly allow
- Test policies in staging before production
- Document all network policies
- Use namespace and pod selectors carefully

---

### Issue 2e: Service Type Changed

**Symptoms:**
```bash
# Can't access frontend from outside cluster
$ curl http://<node-ip>:30080
curl: (7) Failed to connect to <node-ip> port 30080: Connection refused
```

**Diagnosis:**
```bash
# Check service type
kubectl get svc frontend -n workshop-app
NAME       TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
frontend   ClusterIP   10.96.123.456   <none>        80/TCP    10m
```

**Root Cause:**
Service type changed from NodePort to ClusterIP

**Solution Steps:**

1. **Restore NodePort:**
```bash
kubectl patch svc frontend -n workshop-app -p '{
  "spec": {
    "type": "NodePort",
    "ports": [{
      "port": 80,
      "targetPort": 80,
      "nodePort": 30080
    }]
  }
}'
```

2. **Verify:**
```bash
kubectl get svc frontend -n workshop-app
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl http://${NODE_IP}:30080/health
```

**Service Types:**
- **ClusterIP**: Internal only
- **NodePort**: Exposes on node IPs
- **LoadBalancer**: Cloud load balancer
- **ExternalName**: DNS CNAME

**Cleanup Scenario 2:**
```bash
# NetworkPolicies were already fixed
# Services were patched, no cleanup needed
```

---

## Scenario 3: Storage & StatefulSets {#scenario-3}

### Concepts Covered
- PersistentVolumes (PV) and PersistentVolumeClaims (PVC)
- StorageClasses
- StatefulSets and stable storage
- Volume mounting
- Storage provisioning

### Activate Scenario
```bash
bash workshop-scripts/03-break-storage.sh
```

### Issue 3a: Missing PVC for StatefulSet

**Symptoms:**
```bash
$ kubectl get pods -n workshop-app | grep mysql
mysql-0   0/1   Pending   0   5m

$ kubectl get statefulset mysql -n workshop-app
NAME    READY   AGE
mysql   0/1     5m
```

**Diagnosis:**
```bash
# Check pod events
kubectl describe pod mysql-0 -n workshop-app
# Events:
#   Warning  FailedScheduling  persistentvolumeclaim "mysql-pvc" not found

# Check PVCs
kubectl get pvc -n workshop-app
# mysql-pvc is missing!
```

**Root Cause:**
PVC was deleted while StatefulSet was scaled down

**Solution Steps:**

1. **Recreate PVC:**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
  namespace: workshop-app
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
```

2. **Scale up StatefulSet:**
```bash
kubectl scale statefulset mysql -n workshop-app --replicas=1
```

3. **Wait for pod to be ready:**
```bash
kubectl wait --for=condition=ready pod mysql-0 -n workshop-app --timeout=120s
```

4. **Verify:**
```bash
kubectl get pvc mysql-pvc -n workshop-app
kubectl get pod mysql-0 -n workshop-app
```

**Key Learning:**
- StatefulSets require persistent storage
- PVCs must exist before pods can be scheduled
- StatefulSets use volumeClaimTemplates for automatic PVC creation

---

### Issue 3b: Non-existent StorageClass

**Symptoms:**
```bash
$ kubectl get pvc broken-pvc -n workshop-app
NAME          STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS                    AGE
broken-pvc    Pending                                      non-existent-storage-class      2m
```

**Diagnosis:**
```bash
# Check PVC status
kubectl describe pvc broken-pvc -n workshop-app
# Events:
#   Warning  ProvisioningFailed  storageclass.storage.k8s.io 
#   "non-existent-storage-class" not found

# List available storage classes
kubectl get storageclass
```

**Root Cause:**
PVC references a StorageClass that doesn't exist

**Solution Steps:**

1. **Check available storage classes:**
```bash
kubectl get storageclass
```

2. **Option A - Use existing storage class:**
```bash
# Get default storage class name
SC_NAME=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')

# Patch PVC
kubectl patch pvc broken-pvc -n workshop-app -p "{
  \"spec\": {
    \"storageClassName\": \"${SC_NAME}\"
  }
}"
```

3. **Option B - Remove storageClassName to use default:**
```bash
kubectl patch pvc broken-pvc -n workshop-app --type json -p '[
  {"op": "remove", "path": "/spec/storageClassName"}
]'
```

4. **Option C - Delete and recreate:**
```bash
kubectl delete pvc broken-pvc -n workshop-app
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: broken-pvc
  namespace: workshop-app
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  # storageClassName omitted = use default
EOF
```

5. **Verify:**
```bash
kubectl get pvc broken-pvc -n workshop-app
# STATUS should be Bound
```

---

### Issue 3c: StatefulSet with Wrong ServiceName

**Symptoms:**
```bash
$ kubectl get pods -n workshop-app | grep mysql
# Pod might be running but DNS resolution fails

$ kubectl exec -it <pod> -n workshop-app -- nslookup mysql-0.mysql.workshop-app.svc.cluster.local
# Server can't find mysql-0.mysql.workshop-app.svc.cluster.local
```

**Diagnosis:**
```bash
# Check StatefulSet spec
kubectl get statefulset mysql -n workshop-app -o yaml | grep serviceName:
# serviceName: wrong-service

# Check if headless service exists
kubectl get svc wrong-service -n workshop-app
# Error: service "wrong-service" not found
```

**Root Cause:**
StatefulSet serviceName points to non-existent service

**Solution Steps:**

1. **Fix StatefulSet serviceName:**
```bash
kubectl patch statefulset mysql -n workshop-app -p '{
  "spec": {
    "serviceName": "mysql"
  }
}'
```

2. **Restart pods (if needed):**
```bash
kubectl delete pod mysql-0 -n workshop-app
# StatefulSet will recreate it
```

3. **Verify DNS:**
```bash
kubectl wait --for=condition=ready pod mysql-0 -n workshop-app --timeout=120s
kubectl exec -it mysql-0 -n workshop-app -- hostname -f
# Should output: mysql-0.mysql.workshop-app.svc.cluster.local
```

**StatefulSet DNS:**
```
<pod-name>.<service-name>.<namespace>.svc.cluster.local
mysql-0.mysql.workshop-app.svc.cluster.local
```

---

### Issue 3d: Invalid Volume Mount

**Symptoms:**
```bash
$ kubectl get pods -n workshop-app | grep broken-mount
broken-mount   0/1   CreateContainerConfigError   0   1m
```

**Diagnosis:**
```bash
# Describe pod
kubectl describe pod broken-mount -n workshop-app
# Events:
#   Warning  Failed  Error: failed to generate container 
#   "xxx" spec: failed to generate spec: path "/nonexistent/path/that/will/fail/missing/subdirectory" 
#   is outside of mountpoint "/nonexistent/path/that/will/fail"
```

**Root Cause:**
Volume mount uses subPath that doesn't exist in the volume

**Solution Steps:**

1. **Delete broken pod:**
```bash
kubectl delete pod broken-mount -n workshop-app
```

2. **Create corrected pod:**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: fixed-mount
  namespace: workshop-app
spec:
  containers:
  - name: app
    image: nginx:alpine
    volumeMounts:
    - name: data
      mountPath: /usr/share/nginx/html
  volumes:
  - name: data
    emptyDir: {}
EOF
```

3. **Verify:**
```bash
kubectl get pod fixed-mount -n workshop-app
kubectl exec -it fixed-mount -n workshop-app -- ls -la /usr/share/nginx/html
```

**Volume Mount Best Practices:**
- Don't use subPath unless necessary
- Ensure directories exist or use initContainers
- Test mount paths in development first

---

### Issue 3e: Insufficient Storage

**Symptoms:**
```bash
$ kubectl get pvc insufficient-storage -n workshop-app
NAME                   STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
insufficient-storage   Pending                                      standard       5m
```

**Diagnosis:**
```bash
# Describe PVC
kubectl describe pvc insufficient-storage -n workshop-app
# Events:
#   Warning  ProvisioningFailed  Failed to provision volume: 
#   requested storage of 1000Gi exceeds available capacity

# Check PVC request
kubectl get pvc insufficient-storage -n workshop-app -o yaml | grep storage:
```

**Root Cause:**
Requested 1000Gi but cluster doesn't have that much storage

**Solution Steps:**

1. **Check available storage:**
```bash
kubectl get nodes -o json | jq '.items[].status.allocatable.ephemeral-storage'
```

2. **Delete excessive request:**
```bash
kubectl delete pvc insufficient-storage -n workshop-app
kubectl delete pod large-storage-pod -n workshop-app
```

3. **Create reasonable request:**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: reasonable-storage
  namespace: workshop-app
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF
```

**Cleanup Scenario 3:**
```bash
kubectl delete pod broken-mount fixed-mount large-storage-pod -n workshop-app
kubectl delete pvc broken-pvc insufficient-storage reasonable-storage -n workshop-app
```

---

## Scenario 4: ConfigMap, Secrets & Resources {#scenario-4}

### Concepts Covered
- ConfigMaps and configuration management
- Secrets and sensitive data
- Environment variables
- Resource requests and limits
- Liveness and readiness probes
- Quality of Service (QoS) classes

### Activate Scenario
```bash
bash workshop-scripts/04-break-config.sh
```

### Issue 4a: Missing ConfigMap

**Symptoms:**
```bash
$ kubectl get pods -n workshop-app | grep backend
backend-xxx   0/1   CreateContainerConfigError   0   2m
```

**Diagnosis:**
```bash
# Describe pod
kubectl describe pod backend-xxx -n workshop-app
# Events:
#   Warning  Failed  Error: configmap "backend-config" not found

# Check if ConfigMap exists
kubectl get configmap backend-config -n workshop-app
# Error from server (NotFound): configmaps "backend-config" not found
```

**Root Cause:**
ConfigMap was deleted but pods reference it with `envFrom`

**Solution Steps:**

1. **Recreate ConfigMap:**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
  namespace: workshop-app
data:
  API_PORT: "3000"
  CACHE_ENABLED: "true"
  LOG_LEVEL: "info"
  DATABASE_TIMEOUT: "30"
EOF
```

2. **Restart deployment:**
```bash
kubectl rollout restart deployment backend -n workshop-app
kubectl rollout status deployment backend -n workshop-app
```

3. **Verify pods are running:**
```bash
kubectl get pods -n workshop-app -l app=backend
```

4. **Check environment variables:**
```bash
kubectl exec -it <backend-pod> -n workshop-app -- env | grep -E "API_PORT|CACHE_ENABLED"
```

**ConfigMap Best Practices:**
- Use version suffixes (my-config-v1, my-config-v2)
- Never delete ConfigMaps that are in use
- Use ImmutableConfigMaps for critical configs
- Document all ConfigMap keys

---

### Issue 4b: Incorrect Secret Data

**Symptoms:**
```bash
$ kubectl logs mysql-0 -n workshop-app
ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: YES)

$ kubectl get pods -n workshop-app | grep mysql
mysql-0   0/1   CrashLoopBackOff   5   3m
```

**Diagnosis:**
```bash
# Check secret
kubectl get secret mysql-secret -n workshop-app -o yaml
# Data looks base64 encoded but when decoded...

# Decode password
kubectl get secret mysql-secret -n workshop-app -o jsonpath='{.data.password}' | base64 -d
# Output: brokenpassword (not the original: workshop123)
```

**Root Cause:**
Secret was patched with wrong password

**Solution Steps:**

1. **Create correct secret:**
```bash
# Encode correct password
CORRECT_PASSWORD=$(echo -n "workshop123" | base64)

# Patch secret
kubectl patch secret mysql-secret -n workshop-app -p "{
  \"data\": {
    \"password\": \"${CORRECT_PASSWORD}\"
  }
}"
```

2. **Delete pod to restart with new secret:**
```bash
kubectl delete pod mysql-0 -n workshop-app
```

3. **Wait for pod to be ready:**
```bash
kubectl wait --for=condition=ready pod mysql-0 -n workshop-app --timeout=120s
```

4. **Test MySQL connection:**
```bash
kubectl exec -it mysql-0 -n workshop-app -- \
  mysql -u root -pworkshop123 -e "SELECT 1;"
```

**Secret Management Tips:**
- Never commit secrets to Git
- Use external secret management (Vault, AWS Secrets Manager)
- Rotate secrets regularly
- Use RBAC to limit secret access

---

### Issue 4c: Invalid Environment Variable References

**Symptoms:**
```bash
$ kubectl get pods -n workshop-app | grep broken-env
broken-env-xxx   0/1   CreateContainerConfigError   0   1m
```

**Diagnosis:**
```bash
# Describe pod
kubectl describe pod broken-env-xxx -n workshop-app
# Events:
#   Warning  Failed  Error: couldn't find key non-existent-key in ConfigMap 
#   workshop-app/non-existent-configmap
```

**Root Cause:**
Pod references ConfigMap and Secret that don't exist

**Solution Steps:**

1. **Option A - Create missing resources:**
```bash
# Create ConfigMap
kubectl create configmap non-existent-configmap \
  --from-literal=non-existent-key=value \
  -n workshop-app

# Create Secret
kubectl create secret generic non-existent-secret \
  --from-literal=non-existent-key=secretvalue \
  -n workshop-app
```

2. **Option B - Fix deployment to use existing resources:**
```bash
kubectl patch deployment broken-env -n workshop-app --type json -p '[
  {"op": "remove", "path": "/spec/template/spec/containers/0/env"}
]'
```

3. **Option C - Use optional references:**
```bash
kubectl patch deployment broken-env -n workshop-app --type json -p '[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env",
    "value": [
      {
        "name": "CONFIG_VALUE",
        "valueFrom": {
          "configMapKeyRef": {
            "name": "backend-config",
            "key": "API_PORT",
            "optional": true
          }
        }
      }
    ]
  }
]'
```

4. **Verify:**
```bash
kubectl get pods -n workshop-app -l app=broken-env
```

**Environment Variable Sources:**
- Direct values: `value: "literal"`
- ConfigMap: `configMapKeyRef`
- Secret: `secretKeyRef`
- Field references: `fieldRef`
- Resource field: `resourceFieldRef`

---

### Issue 4d: Unrealistic Resource Requests

**Symptoms:**
```bash
$ kubectl get pods -n workshop-app | grep resource-limited
resource-limited-xxx   0/1   Pending   0   5m
```

**Diagnosis:**
```bash
# Describe pod
kubectl describe pod resource-limited-xxx -n workshop-app
# Events:
#   Warning  FailedScheduling  0/1 nodes are available: 
#   1 Insufficient cpu, 1 Insufficient memory

# Check node resources
kubectl describe nodes | grep -A 5 "Allocated resources"
```

**Root Cause:**
Pod requests 10Gi memory and 8 CPUs but node doesn't have that much

**Solution Steps:**

1. **Check node capacity:**
```bash
kubectl get nodes -o json | jq '.items[].status.allocatable'
```

2. **Fix resource requests:**
```bash
kubectl patch deployment resource-limited -n workshop-app -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "app",
          "resources": {
            "requests": {
              "memory": "64Mi",
              "cpu": "100m"
            },
            "limits": {
              "memory": "128Mi",
              "cpu": "200m"
            }
          }
        }]
      }
    }
  }
}'
```

3. **Verify pod is scheduled:**
```bash
kubectl get pods -n workshop-app -l app=resource-limited
```

**Resource Management:**
- **Requests**: Guaranteed resources
- **Limits**: Maximum allowed
- **QoS Classes**:
  - Guaranteed: requests = limits
  - Burstable: requests < limits
  - BestEffort: no requests/limits

---

### Issue 4e: Broken Liveness Probe

**Symptoms:**
```bash
$ kubectl get pods -n workshop-app | grep backend
backend-xxx   0/1   Running   5   3m
# Pod keeps restarting
```

**Diagnosis:**
```bash
# Check pod events
kubectl describe pod backend-xxx -n workshop-app
# Events:
#   Warning  Unhealthy  Liveness probe failed: HTTP probe failed 
#   with statuscode: 404

# Check probe configuration
kubectl get deployment backend -n workshop-app -o yaml | grep -A 10 livenessProbe:
```

**Root Cause:**
Liveness probe checks `/nonexistent` path which returns 404

**Solution Steps:**

1. **Fix liveness probe:**
```bash
kubectl patch deployment backend -n workshop-app --type json -p '[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/livenessProbe",
    "value": {
      "httpGet": {
        "path": "/",
        "port": 3000
      },
      "initialDelaySeconds": 10,
      "periodSeconds": 10
    }
  }
]'
```

2. **Monitor rollout:**
```bash
kubectl rollout status deployment backend -n workshop-app
```

3. **Verify pods are stable:**
```bash
watch kubectl get pods -n workshop-app -l app=backend
# Should show Running with RESTARTS not increasing
```

**Probe Best Practices:**
- **Liveness**: Restart unhealthy containers
- **Readiness**: Remove from service load balancing
- **Startup**: Give slow-starting apps time
- Set appropriate timeouts and thresholds
- Test probes thoroughly before production

---

### Issue 4f: Invalid Readiness Probe

**Symptoms:**
```bash
$ kubectl get pods -n workshop-app | grep broken-probe
broken-probe-xxx   0/1   Running   0   2m
broken-probe-yyy   0/1   Running   0   2m
# Pods running but not ready

$ kubectl get svc -n workshop-app
# Service has no endpoints
```

**Diagnosis:**
```bash
# Check pod readiness
kubectl describe pod broken-probe-xxx -n workshop-app
# Events:
#   Warning  Unhealthy  Readiness probe failed: 
#   Get "http://10.244.0.x:9999/ready": dial tcp 10.244.0.x:9999: connect: connection refused

# Check probe config
kubectl get deployment broken-probe -n workshop-app -o yaml | grep -A 10 readinessProbe:
```

**Root Cause:**
Readiness probe checks wrong port (9999 instead of 80)

**Solution Steps:**

1. **Fix readiness probe:**
```bash
kubectl patch deployment broken-probe -n workshop-app --type json -p '[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/readinessProbe",
    "value": {
      "httpGet": {
        "path": "/",
        "port": 80
      },
      "initialDelaySeconds": 5,
      "periodSeconds": 5
    }
  }
]'
```

2. **Wait for pods to become ready:**
```bash
kubectl wait --for=condition=ready pod -l app=broken-probe -n workshop-app --timeout=60s
```

3. **Verify service has endpoints:**
```bash
kubectl get endpoints -n workshop-app | grep broken-probe
```

**Cleanup Scenario 4:**
```bash
kubectl delete deployment broken-env resource-limited broken-probe -n workshop-app
```

---

## Scenario 5: RBAC, Security & Node Issues {#scenario-5}

### Concepts Covered
- Role-Based Access Control (RBAC)
- ServiceAccounts
- Security Contexts
- Pod Security Standards
- Node selectors and affinity
- Taints and tolerations
- Pod Priority and Preemption

### Activate Scenario
```bash
bash workshop-scripts/05-break-rbac-nodes.sh
```

### Issue 5a: Restrictive Security Context

**Symptoms:**
```bash
$ kubectl get pods -n workshop-app | grep security-restricted
security-restricted   0/1   CreateContainerConfigError   0   2m
```

**Diagnosis:**
```bash
# Describe pod
kubectl describe pod security-restricted -n workshop-app
# Events:
#   Warning  Failed  Error: container has runAsNonRoot and image will run as root

# Check security context
kubectl get pod security-restricted -n workshop-app -o yaml | grep -A 20 securityContext:
```

**Root Cause:**
- Pod securityContext requires runAsNonRoot: true
- nginx image runs as root by default
- Conflict between security requirements and image

**Solution Steps:**

1. **Option A - Use non-root nginx image:**
```bash
kubectl delete pod security-restricted -n workshop-app

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: security-fixed
  namespace: workshop-app
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 101
    fsGroup: 101
  containers:
  - name: app
    image: nginxinc/nginx-unprivileged:alpine
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
    ports:
    - containerPort: 8080
    volumeMounts:
    - name: cache
      mountPath: /var/cache/nginx
    - name: run
      mountPath: /var/run
  volumes:
  - name: cache
    emptyDir: {}
  - name: run
    emptyDir: {}
EOF
```

2. **Option B - Relax security context:**
```bash
# Only if security requirements allow
kubectl delete pod security-restricted -n workshop-app

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: security-relaxed
  namespace: workshop-app
spec:
  containers:
  - name: app
    image: nginx:alpine
    ports:
    - containerPort: 80
EOF
```

3. **Verify:**
```bash
kubectl get pod security-fixed -n workshop-app
kubectl logs security-fixed -n workshop-app
```

**Security Context Best Practices:**
- Always use non-root containers when possible
- Set readOnlyRootFilesystem: true
- Disable privilege escalation
- Use Pod Security Standards (restricted, baseline, privileged)
- Scan images for vulnerabilities

---

### Issue 5b: RBAC Permissions Missing

**Symptoms:**
```bash
$ kubectl logs rbac-restricted-xxx -n workshop-app
Error from server (Forbidden): pods is forbidden: 
User "system:serviceaccount:workshop-app:restricted-sa" 
cannot list resource "pods" in API group "" in the namespace "workshop-app"
```

**Diagnosis:**
```bash
# Check ServiceAccount
kubectl get sa restricted-sa -n workshop-app

# Check what permissions it has
kubectl auth can-i --list --as=system:serviceaccount:workshop-app:restricted-sa -n workshop-app

# Check for roles/rolebindings
kubectl get role,rolebinding -n workshop-app | grep restricted
```

**Root Cause:**
ServiceAccount has no RBAC permissions to list pods

**Solution Steps:**

1. **Create Role with necessary permissions:**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: workshop-app
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
EOF
```

2. **Create RoleBinding:**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: workshop-app
subjects:
- kind: ServiceAccount
  name: restricted-sa
  namespace: workshop-app
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
EOF
```

3. **Verify permissions:**
```bash
kubectl auth can-i get pods \
  --as=system:serviceaccount:workshop-app:restricted-sa \
  -n workshop-app
# Should return: yes
```

4. **Check pod logs:**
```bash
kubectl logs -f deployment/rbac-restricted -n workshop-app
# Should now successfully list pods
```

**RBAC Concepts:**
- **Role**: Permissions within namespace
- **ClusterRole**: Cluster-wide permissions
- **RoleBinding**: Binds Role to subjects
- **ClusterRoleBinding**: Binds ClusterRole to subjects
- **ServiceAccount**: Identity for pods

**Common RBAC Verbs:**
- get, list, watch: Read operations
- create, update, patch: Write operations
- delete, deletecollection: Delete operations
- * : All verbs (use cautiously)

---

### Issue 5c: Unschedulable Pods (Node Selector)

**Symptoms:**
```bash
$ kubectl get pods -n workshop-app | grep unschedulable
unschedulable-xxx   0/1   Pending   0   5m
unschedulable-yyy   0/1   Pending   0   5m
```

**Diagnosis:**
```bash
# Describe pod
kubectl describe pod unschedulable-xxx -n workshop-app
# Events:
#   Warning  FailedScheduling  0/1 nodes are available: 
#   1 node(s) didn't match Pod's node affinity/selector

# Check node selector
kubectl get deployment unschedulable -n workshop-app -o yaml | grep -A 5 nodeSelector:

# Check node labels
kubectl get nodes --show-labels
```

**Root Cause:**
Pod requires nodes with labels `disk-type: ssd` and `gpu: nvidia-v100` but no nodes have these labels

**Solution Steps:**

1. **Option A - Remove node selector:**
```bash
kubectl patch deployment unschedulable -n workshop-app --type json -p '[
  {"op": "remove", "path": "/spec/template/spec/nodeSelector"}
]'
```

2. **Option B - Add labels to nodes (if appropriate):**
```bash
# Only if nodes actually have these characteristics
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl label node $NODE_NAME disk-type=ssd
kubectl label node $NODE_NAME gpu=nvidia-v100
```

3. **Option C - Change to nodeAffinity with preferences:**
```bash
kubectl patch deployment unschedulable -n workshop-app --type json -p '[
  {"op": "remove", "path": "/spec/template/spec/nodeSelector"},
  {
    "op": "add",
    "path": "/spec/template/spec/affinity",
    "value": {
      "nodeAffinity": {
        "preferredDuringSchedulingIgnoredDuringExecution": [
          {
            "weight": 1,
            "preference": {
              "matchExpressions": [
                {
                  "key": "disk-type",
                  "operator": "In",
                  "values": ["ssd"]
                }
              ]
            }
          }
        ]
      }
    }
  }
]'
```

4. **Verify pods are scheduled:**
```bash
kubectl get pods -n workshop-app -l app=unschedulable -o wide
```

**Node Selection Methods:**
- **nodeSelector**: Simple key-value matching
- **nodeAffinity**: Complex rules with required/preferred
- **taints/tolerations**: Repel pods unless they tolerate
- **topologySpreadConstraints**: Even distribution

---

### Issue 5d: Node Taint Preventing Scheduling

**Symptoms:**
```bash
$ kubectl get pods -n workshop-app -o wide
# Most pods stuck in Pending state
```

**Diagnosis:**
```bash
# Check node taints
kubectl describe nodes | grep Taints:
# Taints: workshop=broken:NoSchedule

# Check pod events
kubectl get events -n workshop-app --sort-by='.lastTimestamp' | grep FailedScheduling
```

**Root Cause:**
Node was tainted with `workshop=broken:NoSchedule` and pods don't have matching tolerations

**Solution Steps:**

1. **Remove taint from node:**
```bash
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl taint nodes $NODE_NAME workshop=broken:NoSchedule-
```

2. **Verify pods are scheduled:**
```bash
watch kubectl get pods -n workshop-app
```

3. **Alternative - Add toleration to pods:**
```bash
# If you want to keep the taint, add tolerations
kubectl patch deployment <deployment-name> -n workshop-app -p '{
  "spec": {
    "template": {
      "spec": {
        "tolerations": [{
          "key": "workshop",
          "operator": "Equal",
          "value": "broken",
          "effect": "NoSchedule"
        }]
      }
    }
  }
}'
```

**Taint Effects:**
- **NoSchedule**: Don't schedule new pods
- **PreferNoSchedule**: Try not to schedule
- **NoExecute**: Evict existing pods

**Common Taints:**
- `node.kubernetes.io/not-ready`: Node not ready
- `node.kubernetes.io/unreachable`: Node unreachable
- `node.kubernetes.io/disk-pressure`: Low disk space
- `node.kubernetes.io/memory-pressure`: Low memory

---

### Issue 5e: High Priority Pods Causing Disruption

**Symptoms:**
```bash
$ kubectl get pods -n workshop-app
# Some pods being evicted
# Pods with "Evicted" status

$ kubectl get events -n workshop-app | grep Preempted
```

**Diagnosis:**
```bash
# Check priority classes
kubectl get priorityclass

# Check pod priorities
kubectl get pods -n workshop-app -o custom-columns=NAME:.metadata.name,PRIORITY:.spec.priority

# Check which pods were preempted
kubectl get pods -n workshop-app -o json | jq -r '.items[] | select(.status.reason=="Preempted") | .metadata.name'
```

**Root Cause:**
High priority pods (priority 1000000) are preempting lower priority pods

**Solution Steps:**

1. **Scale down high priority deployment:**
```bash
kubectl scale deployment high-priority-disruptor -n workshop-app --replicas=1
```

2. **Lower the priority:**
```bash
kubectl patch deployment high-priority-disruptor -n workshop-app -p '{
  "spec": {
    "template": {
      "spec": {
        "priorityClassName": ""
      }
    }
  }
}'
```

3. **Or delete the deployment:**
```bash
kubectl delete deployment high-priority-disruptor -n workshop-app
```

4. **Delete the problematic priority class:**
```bash
kubectl delete priorityclass super-high-priority
```

5. **Verify cluster stability:**
```bash
kubectl get pods -n workshop-app
# All pods should be Running
```

**Priority and Preemption:**
- Higher priority pods can preempt (evict) lower priority ones
- Use for critical system components only
- Default priority is 0
- Negative priorities are possible

---

### Issue 5f: Conflicting Affinity Rules

**Symptoms:**
```bash
$ kubectl get pods -n workshop-app | grep affinity-conflict
affinity-conflict-xxx   0/1   Pending   0   3m
affinity-conflict-yyy   0/1   Pending   0   3m
```

**Diagnosis:**
```bash
# Describe pod
kubectl describe pod affinity-conflict-xxx -n workshop-app
# Events:
#   Warning  FailedScheduling  0/1 nodes are available: 
#   1 node(s) didn't match pod anti-affinity rules

# Check affinity rules
kubectl get deployment affinity-conflict -n workshop-app -o yaml | grep -A 30 affinity:
```

**Root Cause:**
- podAntiAffinity requires pods to be on different nodes (replicas=3)
- nodeAffinity requires specific node that doesn't exist
- Only 1 node in cluster = impossible to satisfy both

**Solution Steps:**

1. **Option A - Remove conflicting rules:**
```bash
kubectl patch deployment affinity-conflict -n workshop-app --type json -p '[
  {"op": "remove", "path": "/spec/template/spec/affinity/nodeAffinity"},
  {"op": "replace", "path": "/spec/template/spec/affinity/podAntiAffinity/requiredDuringSchedulingIgnoredDuringExecution/0/labelSelector", "value": {"matchLabels": {"app": "affinity-conflict"}}},
  {"op": "replace", "path": "/spec/replicas", "value": 1}
]'
```

2. **Option B - Use preferred instead of required:**
```bash
kubectl patch deployment affinity-conflict -n workshop-app --type json -p '[
  {
    "op": "replace",
    "path": "/spec/template/spec/affinity",
    "value": {
      "podAntiAffinity": {
        "preferredDuringSchedulingIgnoredDuringExecution": [{
          "weight": 100,
          "podAffinityTerm": {
            "labelSelector": {
              "matchLabels": {
                "app": "affinity-conflict"
              }
            },
            "topologyKey": "kubernetes.io/hostname"
          }
        }]
      }
    }
  }
]'
```

3. **Option C - Simply delete:**
```bash
kubectl delete deployment affinity-conflict -n workshop-app
```

4. **Verify:**
```bash
kubectl get pods -n workshop-app | grep affinity
```

**Affinity Types:**
- **nodeAffinity**: Schedule on specific nodes
- **podAffinity**: Schedule near certain pods
- **podAntiAffinity**: Schedule away from certain pods
- **required**: Hard requirement (must satisfy)
- **preferred**: Soft preference (try to satisfy)

**Cleanup Scenario 5:**
```bash
kubectl delete pod security-restricted security-fixed security-relaxed -n workshop-app
kubectl delete deployment rbac-restricted unschedulable high-priority-disruptor affinity-conflict -n workshop-app
kubectl delete role pod-reader -n workshop-app
kubectl delete rolebinding pod-reader-binding -n workshop-app
kubectl delete priorityclass super-high-priority
kubectl delete sa restricted-sa -n workshop-app

# Remove node taint if still present
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl taint nodes $NODE_NAME workshop- || true
```

---

## Quick Reference Commands {#quick-reference}

### Essential Troubleshooting Commands

```bash
# Pod troubleshooting
kubectl get pods -n <namespace> -o wide
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
kubectl logs -f <pod-name> -n <namespace>
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
kubectl get events -n <namespace> --watch
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Deployments
kubectl get deployment -n <namespace>
kubectl describe deployment <name> -n <namespace>
kubectl rollout status deployment/<name> -n <namespace>
kubectl rollout history deployment/<name> -n <namespace>
kubectl rollout undo deployment/<name> -n <namespace>

# Services and networking
kubectl get svc -n <namespace>
kubectl get endpoints -n <namespace>
kubectl describe svc <name> -n <namespace>
kubectl get networkpolicies -n <namespace>

# Storage
kubectl get pv
kubectl get pvc -n <namespace>
kubectl describe pvc <name> -n <namespace>
kubectl get storageclass

# ConfigMaps and Secrets
kubectl get configmap -n <namespace>
kubectl get secret -n <namespace>
kubectl describe configmap <name> -n <namespace>
kubectl get secret <name> -n <namespace> -o yaml

# Nodes
kubectl get nodes
kubectl describe node <node-name>
kubectl top nodes
kubectl get nodes --show-labels

# RBAC
kubectl get sa -n <namespace>
kubectl get role,rolebinding -n <namespace>
kubectl auth can-i <verb> <resource> --as=<user>
kubectl auth can-i --list --as=<user> -n <namespace>

# Resource usage
kubectl top nodes
kubectl top pods -n <namespace>
kubectl describe resourcequota -n <namespace>

# Debug pod
kubectl run debug --image=busybox:latest --rm -it --restart=Never -- sh
kubectl debug <pod-name> -it --image=ubuntu
```

### Common Issues and Quick Fixes

| Issue | Quick Check | Quick Fix |
|-------|-------------|-----------|
| ImagePullBackOff | `kubectl describe pod` | Fix image name/tag |
| CrashLoopBackOff | `kubectl logs --previous` | Fix app config/command |
| Pending pod | `kubectl describe pod` | Check resources/taints |
| Service not working | `kubectl get endpoints` | Check selector labels |
| DNS not resolving | Test from pod: `nslookup` | Check CoreDNS |
| ConfigMap missing | `kubectl get cm` | Recreate ConfigMap |
| No RBAC permissions | `kubectl auth can-i` | Create Role/RoleBinding |
| PVC pending | `kubectl describe pvc` | Check StorageClass |

### JSON Path Examples

```bash
# Get pod IPs
kubectl get pods -n <namespace> -o jsonpath='{.items[*].status.podIP}'

# Get node names
kubectl get nodes -o jsonpath='{.items[*].metadata.name}'

# Get container images
kubectl get pods -n <namespace> -o jsonpath='{.items[*].spec.containers[*].image}'

# Get pod with most restarts
kubectl get pods -n <namespace> --sort-by='.status.containerStatuses[0].restartCount'

# Get pods not running
kubectl get pods --all-namespaces --field-selector=status.phase!=Running
```

### Complete Cleanup

```bash
# Clean up all workshop resources
kubectl delete namespace workshop-app

# Or selectively clean up broken resources
kubectl delete deployment -l scenario -n workshop-app
kubectl delete pod -l scenario -n workshop-app
kubectl delete svc -l scenario -n workshop-app
kubectl delete pvc -l scenario -n workshop-app

# Remove taints
kubectl taint nodes --all workshop-

# Remove priority classes
kubectl delete priorityclass super-high-priority
```

---

## Workshop Completion

### What You've Learned

1. **Pod Lifecycle & Troubleshooting**
   - ImagePullBackOff resolution
   - CrashLoopBackOff debugging
   - OOMKilled diagnosis
   - Resource limit tuning

2. **Networking**
   - Service selector matching
   - DNS troubleshooting
   - NetworkPolicy management
   - Service type configuration

3. **Storage**
   - PV/PVC management
   - StatefulSet dependencies
   - Storage class selection
   - Volume mounting

4. **Configuration**
   - ConfigMap management
   - Secret handling
   - Environment variables
   - Liveness/readiness probes

5. **Security & Scheduling**
   - RBAC configuration
   - Security contexts
   - Node selection
   - Taints and tolerations
   - Pod priority

### Next Steps

1. Practice these scenarios multiple times
2. Create your own breaking scenarios
3. Learn Helm for package management
4. Explore service mesh (Istio, Linkerd)
5. Implement monitoring (Prometheus, Grafana)
6. Study disaster recovery
7. Learn multi-cluster management

### Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Kubernetes Troubleshooting Guide](https://kubernetes.io/docs/tasks/debug/)
- [CKAD Exam](https://www.cncf.io/certification/ckad/)
- [CKA Exam](https://www.cncf.io/certification/cka/)

---

**Workshop Version:** 1.0  
**Last Updated:** September 2025  
