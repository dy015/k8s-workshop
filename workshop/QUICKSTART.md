# Kubernetes Workshop - Quick Start Card

## 🚀 Setup (One-Time)

```bash
# 1. Make executable
chmod +x k8s-manager-final.sh workshop-scripts/*.sh

# 2. Install K8s (if needed - CentOS 9 Stream only)
sudo ./k8s-manager-final.sh install

# 3. Start workshop
cd workshop-scripts/
./workshop-manager.sh
```

## 📋 Workshop Flow

```
Deploy App → Break Things → Investigate → Fix → Repeat
```

## 🎯 Five Scenarios

| # | Scenario | Difficulty | Time | Topics |
|---|----------|------------|------|--------|
| 1 | Pod Issues | ⭐ Beginner | 30m | ImagePull, Crashes, OOM |
| 2 | Networking | ⭐⭐ Medium | 45m | Services, DNS, NetPol |
| 3 | Storage | ⭐⭐ Medium | 45m | PVC, StatefulSets |
| 4 | Configuration | ⭐⭐ Medium | 45m | ConfigMap, Secrets, Probes |
| 5 | RBAC & Nodes | ⭐⭐⭐ Hard | 60m | Security, Scheduling |

## 🔍 Essential Commands

```bash
# The Big Three (use these first!)
kubectl get pods -n workshop-app
kubectl describe pod <pod-name> -n workshop-app
kubectl logs <pod-name> -n workshop-app

# Events (your best friend!)
kubectl get events -n workshop-app --sort-by='.lastTimestamp'

# Services
kubectl get svc,endpoints -n workshop-app

# Everything
kubectl get all -n workshop-app
```

## 🚨 Quick Troubleshooting

| Status | Meaning | First Check |
|--------|---------|-------------|
| `ImagePullBackOff` | Can't pull image | `describe` → Events |
| `CrashLoopBackOff` | App crashes | `logs --previous` |
| `Pending` | Can't schedule | `describe` → Events |
| `Running` but not `Ready` | Health checks fail | `describe` → Probes |
| `Error` | Command failed | `logs` |

## 📚 Files You Have

```
workshop-scripts/
├── 00-deploy-app.sh              # Deploy application
├── 01-break-pods.sh              # Scenario 1
├── 02-break-networking.sh        # Scenario 2
├── 03-break-storage.sh           # Scenario 3
├── 04-break-config.sh            # Scenario 4
├── 05-break-rbac-nodes.sh        # Scenario 5
└── workshop-manager.sh           # Interactive menu

Documentation/
├── README.md                     # Full guide
├── TROUBLESHOOTING-GUIDE.md      # All solutions
└── WORKSHOP-SUMMARY.md           # Complete overview
```

## ⚡ Speed Commands

```bash
# Quick status
kubectl get pods -n workshop-app

# Describe everything
kubectl describe pod <pod-name> -n workshop-app | less

# Follow logs
kubectl logs -f <pod-name> -n workshop-app

# Execute in pod
kubectl exec -it <pod-name> -n workshop-app -- sh

# Test connectivity
kubectl exec -it <pod> -n workshop-app -- curl backend:3000

# Check DNS
kubectl exec -it <pod> -n workshop-app -- nslookup backend
```

## 🧹 Cleanup

```bash
# After each scenario
kubectl delete deployment -l scenario -n workshop-app

# Reset app
kubectl delete namespace workshop-app
./00-deploy-app.sh

# Complete cleanup
kubectl delete namespace workshop-app
```

## 💡 Pro Tips

1. **Always check events first** - `kubectl describe` shows events
2. **Use --previous for crashed pods** - `kubectl logs --previous`
3. **Labels are critical** - Services use selectors to find pods
4. **Endpoints = Service + Matching Pods** - No endpoints? Check labels
5. **When stuck** - Check the TROUBLESHOOTING-GUIDE.md

## 🎓 Learning Path

```
Beginner:   Day 1-2   → Scenario 1
            Day 3-4   → Scenario 2
            
Intermediate: Week 1  → Scenarios 1-3
             Week 2  → Scenario 4

Advanced:    Day 1    → All scenarios
```

## 📞 Help

```bash
# Workshop manager (interactive)
./workshop-manager.sh

# Check app status
kubectl get all -n workshop-app

# View guide
less TROUBLESHOOTING-GUIDE.md

# Show commands
./workshop-manager.sh  # Select option 12
```

## 🎯 Success Criteria

- [ ] Can identify pod issues in <5 minutes
- [ ] Knows when to use describe vs logs
- [ ] Understands service selectors
- [ ] Can debug DNS issues
- [ ] Comfortable with ConfigMaps/Secrets
- [ ] Completed all 5 scenarios
- [ ] Can explain root causes

## 🚀 After Workshop

1. ✅ Practice scenarios 2-3 times each
2. ✅ Create your own breaking scenarios
3. ✅ Apply to your production clusters
4. ✅ Share knowledge with team
5. ✅ Consider CKA/CKAD certification

---

**Remember:** Breaking things is the best way to learn how to fix them!

**Version:** 1.0 | **K8s:** 1.28+ | **Updated:** Sept 2025

---

## 🔑 Commands Cheat Sheet (Back of Card)

```bash
# PODS
kubectl get pods -n workshop-app -o wide
kubectl describe pod <pod> -n workshop-app
kubectl logs <pod> -n workshop-app [--previous] [-f]
kubectl exec -it <pod> -n workshop-app -- sh
kubectl delete pod <pod> -n workshop-app

# DEPLOYMENTS
kubectl get deployment -n workshop-app
kubectl describe deployment <name> -n workshop-app
kubectl rollout status deployment/<name> -n workshop-app
kubectl rollout restart deployment/<name> -n workshop-app
kubectl scale deployment <name> --replicas=3 -n workshop-app

# SERVICES
kubectl get svc,endpoints -n workshop-app
kubectl describe svc <name> -n workshop-app
kubectl get endpoints <name> -n workshop-app

# EVENTS (MOST IMPORTANT!)
kubectl get events -n workshop-app --sort-by='.lastTimestamp'
kubectl get events -n workshop-app --watch

# STORAGE
kubectl get pv,pvc -n workshop-app
kubectl describe pvc <name> -n workshop-app

# CONFIGURATION
kubectl get configmap,secret -n workshop-app
kubectl describe configmap <name> -n workshop-app
kubectl get secret <name> -n workshop-app -o yaml

# NODES
kubectl get nodes [--show-labels]
kubectl describe node <name>
kubectl top nodes

# NAMESPACES
kubectl get all -n workshop-app
kubectl describe namespace workshop-app

# DEBUG
kubectl run debug --image=busybox --rm -it -- sh
kubectl debug <pod> -it --image=ubuntu -n workshop-app

# CLEANUP
kubectl delete <resource> <name> -n workshop-app
kubectl delete -l scenario -n workshop-app
kubectl delete namespace workshop-app
```

---

**Print this card and keep it handy during the workshop!**
