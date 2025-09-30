# Kubernetes Troubleshooting Workshop

## 🎯 Workshop Overview

A comprehensive, hands-on Kubernetes troubleshooting workshop designed for **K8s Admins, DevOps Engineers, and SREs**. This workshop covers all major Kubernetes concepts through realistic breaking scenarios.

**Duration:** 4-6 hours  
**Difficulty:** Beginner to Advanced  
**Prerequisites:** Basic Kubernetes knowledge, cluster with kubectl access

---

## 📚 What You'll Learn

### Core Concepts Covered

| Category | Topics |
|----------|--------|
| **Pod Management** | Lifecycle, CrashLoopBackOff, ImagePullBackOff, OOMKilled, Resource limits |
| **Networking** | Services, DNS, Endpoints, NetworkPolicies, Service types |
| **Storage** | PV/PVC, StatefulSets, StorageClasses, Volume mounting |
| **Configuration** | ConfigMaps, Secrets, Environment variables, Probes |
| **Security & RBAC** | ServiceAccounts, Roles, SecurityContext, Pod Security |
| **Scheduling** | Node selectors, Affinity, Taints/Tolerations, Priority |

---

## 🚀 Quick Start

### Step 1: Setup Kubernetes Cluster

```bash
# Use the provided K8s installation script
chmod +x k8s-deploy.sh
sudo ./k8s-deploy.sh install
```

### Step 2: Deploy Workshop Application

```bash
# Navigate to workshop directory
cd workshop/

# Make scripts executable
chmod +x *.sh

# Deploy the multi-tier application
bash 00-deploy-app.sh
```

**Wait for deployment to complete (2-3 minutes)**

### Step 3: Verify Application

```bash
# Check all components
kubectl get all -n workshop-app

# Test application
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl http://${NODE_IP}:30080/health
```

You should see: `healthy`

---

## 🔧 Workshop Structure

### Application Architecture

```
Internet
   │
   ▼
┌─────────────────────┐
│  Frontend (nginx)   │  NodePort: 30080
│   2 replicas        │  Serves static content
└──────────┬──────────┘  Proxies to backend
           │
           ▼
┌─────────────────────┐
│  Backend (API)      │  ClusterIP: 3000
│   3 replicas        │  HPA enabled (2-10)
│   Auto-scaling      │  Handles business logic
└──────┬──────┬───────┘
       │      │
       │      └─────────┐
       ▼                ▼
┌──────────┐      ┌──────────┐
│  MySQL   │      │  Redis   │
│StatefulSet│      │  Cache   │
│ 1 replica│      │1 replica │
└──────────┘      └──────────┘
```

### Resources Deployed

- **Frontend**: 2 nginx pods with custom config
- **Backend**: 3 API pods with HPA (scales 2-10)
- **Database**: 1 MySQL StatefulSet with persistent storage
- **Cache**: 1 Redis deployment
- **ConfigMaps**: Application configuration
- **Secrets**: Database credentials
- **NetworkPolicies**: Backend traffic rules
- **Services**: ClusterIP and NodePort

---

## 🎭 Breaking Scenarios

### Scenario 1: Pod Issues (Beginner)
**File:** `01-break-pods.sh`  
**Topics:** ImagePullBackOff, CrashLoopBackOff, OOMKilled  
**Time:** 30-45 minutes

```bash
bash 01-break-pods.sh
```

**What Gets Broken:**
- Deployment with non-existent image
- Pod that crashes immediately
- Pod with insufficient memory

### Scenario 2: Networking (Intermediate)
**File:** `02-break-networking.sh`  
**Topics:** Services, DNS, NetworkPolicies  
**Time:** 45-60 minutes

```bash
bash 02-break-networking.sh
```

**What Gets Broken:**
- Service selector mismatch
- Wrong service ports
- CoreDNS misconfiguration
- Restrictive NetworkPolicy
- Service type change

### Scenario 3: Storage (Intermediate)
**File:** `03-break-storage.sh`  
**Topics:** PV/PVC, StatefulSets, Volume mounting  
**Time:** 45-60 minutes

```bash
bash 03-break-storage.sh
```

**What Gets Broken:**
- Missing PVC
- Non-existent StorageClass
- Wrong StatefulSet serviceName
- Invalid volume mount paths
- Insufficient storage requests

### Scenario 4: Configuration (Intermediate)
**File:** `04-break-config.sh`  
**Topics:** ConfigMaps, Secrets, Resources, Probes  
**Time:** 45-60 minutes

```bash
bash 04-break-config.sh
```

**What Gets Broken:**
- Deleted ConfigMap
- Corrupted Secret
- Invalid environment references
- Unrealistic resource requests
- Broken liveness/readiness probes

### Scenario 5: RBAC & Nodes (Advanced)
**File:** `05-break-rbac-nodes.sh`  
**Topics:** RBAC, Security, Node scheduling  
**Time:** 60-90 minutes

```bash
bash 05-break-rbac-nodes.sh
```

**What Gets Broken:**
- Restrictive security contexts
- Missing RBAC permissions
- Impossible node selectors
- Node taints
- Conflicting affinity rules
- Pod priority preemption

---

## 📖 Using the Workshop

### Recommended Approach

1. **Deploy Application First**
   ```bash
   bash 00-deploy-app.sh
   ```

2. **Choose a Scenario**
   ```bash
   bash 01-break-pods.sh
   ```

3. **Investigate Issues**
   ```bash
   kubectl get pods -n workshop-app
   kubectl describe pod <pod-name> -n workshop-app
   kubectl logs <pod-name> -n workshop-app
   ```

4. **Refer to Solutions Guide**
   - Open `TROUBLESHOOTING-GUIDE.md`
   - Find your scenario
   - Try to solve before looking at solutions
   - Review the solution steps
   - Understand the root cause

5. **Clean Up Broken Resources**
   ```bash
   # Each scenario has cleanup steps in the guide
   kubectl delete deployment <broken-deployment> -n workshop-app
   ```

6. **Move to Next Scenario**

### Self-Paced Learning

- Spend 15-20 minutes investigating each issue
- Use `kubectl describe` and `kubectl logs` extensively
- Look at events: `kubectl get events -n workshop-app`
- Only check solutions after attempting yourself

### Team Workshop

- Divide into teams of 2-3
- Each team gets a scenario
- 20 minutes to diagnose
- 10 minutes to fix
- 5 minutes to present findings

---

## 🛠️ Essential Commands Reference

### Pod Troubleshooting
```bash
# List all pods
kubectl get pods -n workshop-app -o wide

# Describe pod (most useful!)
kubectl describe pod <pod-name> -n workshop-app

# View logs
kubectl logs <pod-name> -n workshop-app
kubectl logs <pod-name> -n workshop-app --previous
kubectl logs -f <pod-name> -n workshop-app

# Execute commands in pod
kubectl exec -it <pod-name> -n workshop-app -- sh
kubectl exec -it <pod-name> -n workshop-app -- curl backend:3000

# Debug with temporary pod
kubectl run debug --image=busybox --rm -it --restart=Never -- sh
```

### Events and Debugging
```bash
# View events (critical for troubleshooting!)
kubectl get events -n workshop-app --sort-by='.lastTimestamp'
kubectl get events -n workshop-app --watch

# Resource status
kubectl get all -n workshop-app
kubectl get pods,svc,deploy,sts -n workshop-app
```

### Services and Networking
```bash
# Check services
kubectl get svc -n workshop-app

# Check endpoints (do pods match?)
kubectl get endpoints -n workshop-app

# Describe service
kubectl describe svc <service-name> -n workshop-app

# Test connectivity
kubectl exec -it <pod> -n workshop-app -- curl <service>:3000
kubectl exec -it <pod> -n workshop-app -- nslookup <service>
```

### Storage
```bash
# List PVCs
kubectl get pvc -n workshop-app

# List PVs
kubectl get pv

# Describe PVC
kubectl describe pvc <pvc-name> -n workshop-app

# Check storage classes
kubectl get storageclass
```

### Configuration
```bash
# ConfigMaps
kubectl get configmap -n workshop-app
kubectl describe configmap <name> -n workshop-app

# Secrets
kubectl get secret -n workshop-app
kubectl get secret <name> -n workshop-app -o yaml

# View environment variables in pod
kubectl exec <pod> -n workshop-app -- env
```

### RBAC and Security
```bash
# Check ServiceAccounts
kubectl get sa -n workshop-app

# Check permissions
kubectl auth can-i list pods --as=system:serviceaccount:workshop-app:restricted-sa

# List roles and bindings
kubectl get role,rolebinding -n workshop-app
```

### Nodes and Scheduling
```bash
# List nodes
kubectl get nodes
kubectl get nodes --show-labels

# Describe node
kubectl describe node <node-name>

# Check resource usage
kubectl top nodes
kubectl top pods -n workshop-app

# Check taints
kubectl describe nodes | grep Taints
```

---

## 🔥 Common Issues Quick Reference

| Symptom | Likely Cause | First Check |
|---------|--------------|-------------|
| Pod: `ImagePullBackOff` | Wrong image name/tag | `kubectl describe pod` → Events |
| Pod: `CrashLoopBackOff` | App crashes on start | `kubectl logs --previous` |
| Pod: `Pending` | Resource constraints | `kubectl describe pod` → Events |
| Pod: `OOMKilled` | Memory limit too low | Check resources in pod spec |
| Pod: `Error` | Command failed | `kubectl logs` |
| Service: No endpoints | Selector mismatch | Compare svc selector to pod labels |
| Can't resolve DNS | CoreDNS issue | Check CoreDNS pods in kube-system |
| PVC: `Pending` | No StorageClass | `kubectl describe pvc` |
| Can't access service | NetworkPolicy | Check NetworkPolicies |
| RBAC error | Missing permissions | `kubectl auth can-i` |

---

## 🧹 Cleanup

### Clean Up Specific Scenario

After each scenario, broken resources can be cleaned up:
```bash
# Remove broken deployments
kubectl delete deployment -l scenario -n workshop-app

# Remove broken pods
kubectl delete pod -l scenario -n workshop-app

# Remove broken PVCs
kubectl delete pvc -l scenario -n workshop-app
```

### Reset Application

```bash
# Delete and redeploy
kubectl delete namespace workshop-app
bash 00-deploy-app.sh
```

### Complete Cleanup

```bash
# Remove everything
kubectl delete namespace workshop-app

# Remove any priority classes
kubectl delete priorityclass super-high-priority

# Remove node taints
kubectl taint nodes --all workshop-
```

---

## 📊 Workshop Progress Tracker

Track your progress through the workshop:

- [ ] **Setup**
  - [ ] Kubernetes cluster installed
  - [ ] kubectl configured
  - [ ] Application deployed successfully

- [ ] **Scenario 1: Pod Issues** (30-45 min)
  - [ ] Fixed ImagePullBackOff
  - [ ] Fixed CrashLoopBackOff
  - [ ] Fixed OOMKilled

- [ ] **Scenario 2: Networking** (45-60 min)
  - [ ] Fixed service selector
  - [ ] Fixed service ports
  - [ ] Fixed CoreDNS
  - [ ] Fixed NetworkPolicy
  - [ ] Fixed service type

- [ ] **Scenario 3: Storage** (45-60 min)
  - [ ] Fixed missing PVC
  - [ ] Fixed StorageClass issue
  - [ ] Fixed StatefulSet
  - [ ] Fixed volume mount
  - [ ] Fixed storage request

- [ ] **Scenario 4: Configuration** (45-60 min)
  - [ ] Fixed ConfigMap issue
  - [ ] Fixed Secret issue
  - [ ] Fixed environment variables
  - [ ] Fixed resource limits
  - [ ] Fixed liveness probe
  - [ ] Fixed readiness probe

- [ ] **Scenario 5: RBAC & Nodes** (60-90 min)
  - [ ] Fixed security context
  - [ ] Fixed RBAC permissions
  - [ ] Fixed node selector
  - [ ] Fixed node taint
  - [ ] Fixed pod priority
  - [ ] Fixed affinity rules

---

## 🎓 Learning Outcomes

By completing this workshop, you will be able to:

1. **Diagnose and fix pod startup issues**
   - Image pull failures
   - Container crashes
   - Resource constraints

2. **Troubleshoot networking problems**
   - Service discovery issues
   - DNS resolution
   - NetworkPolicy configuration

3. **Manage storage effectively**
   - PV/PVC lifecycle
   - StatefulSet storage requirements
   - StorageClass selection

4. **Handle configuration properly**
   - ConfigMap and Secret management
   - Environment variable injection
   - Health check configuration

5. **Implement security best practices**
   - RBAC configuration
   - Security contexts
   - Pod security standards

6. **Control pod scheduling**
   - Node selection strategies
   - Affinity and anti-affinity
   - Taints and tolerations

---

## 📚 Additional Resources

### Documentation
- [Kubernetes Official Docs](https://kubernetes.io/docs/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Troubleshooting Applications](https://kubernetes.io/docs/tasks/debug/debug-application/)

### Certifications
- [CKAD (Certified Kubernetes Application Developer)](https://www.cncf.io/certification/ckad/)
- [CKA (Certified Kubernetes Administrator)](https://www.cncf.io/certification/cka/)
- [CKS (Certified Kubernetes Security Specialist)](https://www.cncf.io/certification/cks/)

### Practice Platforms
- [KillerCoda Kubernetes Playgrounds](https://killercoda.com/kubernetes)
- [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)
- [KataKoda Scenarios](https://www.katacoda.com/courses/kubernetes)

---

## 🐛 Troubleshooting the Workshop Itself

### Application Won't Deploy

```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes

# Check if namespace exists
kubectl get namespace workshop-app

# Redeploy
kubectl delete namespace workshop-app
bash 00-deploy-app.sh
```

### Scripts Won't Run

```bash
# Make executable
chmod +x workshop-scripts/*.sh

# Check bash is available
which bash

# Run with explicit bash
bash workshop-scripts/00-deploy-app.sh
```

### Can't Access Application

```bash
# Check service type
kubectl get svc frontend -n workshop-app

# Check NodePort
kubectl get svc frontend -n workshop-app -o jsonpath='{.spec.ports[0].nodePort}'

# Get node IP
kubectl get nodes -o wide

# Test from node
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl http://${NODE_IP}:30080/health
```

---

## 💡 Tips for Success

1. **Read Error Messages Carefully**
   - Events in `kubectl describe` are your best friend
   - Logs often contain the exact error

2. **Use the Right Tool**
   - `kubectl get` - Quick overview
   - `kubectl describe` - Detailed status and events
   - `kubectl logs` - Application output
   - `kubectl exec` - Interactive debugging

3. **Check Dependencies**
   - Services need matching pods
   - Pods need ConfigMaps/Secrets
   - StatefulSets need Services
   - PVCs need StorageClasses

4. **Verify Labels and Selectors**
   - Services use selectors to find pods
   - NetworkPolicies use selectors to apply rules
   - Deployments use selectors to manage pods

5. **Think Systematically**
   - Is the pod running?
   - Are there errors in events?
   - What do the logs say?
   - Can I exec into the pod?
   - Does the service have endpoints?

---

## 🤝 Contributing

Found an issue or want to improve the workshop?

1. Document the problem
2. Create a clear reproduction case
3. Submit suggestions for improvements

---

## 📜 License

This workshop is provided as-is for educational purposes.

---

## 🎉 Have Fun Learning!

Remember: **Breaking things is the best way to learn how to fix them!**

The goal is not to memorize commands, but to understand:
- How Kubernetes components interact
- Where to look when things break
- How to systematically diagnose issues

Happy troubleshooting! 🔧

---

**Version:** 1.0  
**Last Updated:** September 2025  
