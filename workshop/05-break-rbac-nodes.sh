#!/bin/bash
###############################################################################
# Scenario 5: RBAC, Security Context, and Node Issues
# Concepts: RBAC, ServiceAccounts, Security Context, Taints/Tolerations, Node scheduling
# Difficulty: Advanced
###############################################################################

set -e

NAMESPACE="workshop-app"

echo "=============================================="
echo "  BREAKING SCENARIO 5"
echo "  RBAC, Security & Node Issues"
echo "=============================================="
echo ""

echo "[BREAKING] Scenario 5a: Creating pod with restricted security context..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: security-restricted
  namespace: $NAMESPACE
  labels:
    scenario: "5a"
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
  containers:
  - name: app
    image: nginx:alpine
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
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

echo "[BREAKING] Scenario 5b: Creating ServiceAccount without permissions..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: restricted-sa
  namespace: $NAMESPACE
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rbac-restricted
  namespace: $NAMESPACE
  labels:
    scenario: "5b"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rbac-restricted
  template:
    metadata:
      labels:
        app: rbac-restricted
    spec:
      serviceAccountName: restricted-sa
      containers:
      - name: app
        image: bitnami/kubectl:latest
        command: ["/bin/sh"]
        args: ["-c", "while true; do kubectl get pods; sleep 10; done"]
EOF

echo "[BREAKING] Scenario 5c: Creating pod with node selector that doesn't match..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: unschedulable
  namespace: $NAMESPACE
  labels:
    scenario: "5c"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: unschedulable
  template:
    metadata:
      labels:
        app: unschedulable
    spec:
      nodeSelector:
        disk-type: ssd
        gpu: nvidia-v100
      containers:
      - name: app
        image: nginx:alpine
EOF

echo "[BREAKING] Scenario 5d: Adding taint to node..."
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl taint nodes $NODE_NAME workshop=broken:NoSchedule --overwrite

echo "[BREAKING] Scenario 5e: Creating pod with very high priority that disrupts others..."
cat <<EOF | kubectl apply -f -
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: super-high-priority
value: 1000000
globalDefault: false
description: "Super high priority that will evict other pods"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: high-priority-disruptor
  namespace: $NAMESPACE
  labels:
    scenario: "5e"
spec:
  replicas: 5
  selector:
    matchLabels:
      app: high-priority-disruptor
  template:
    metadata:
      labels:
        app: high-priority-disruptor
    spec:
      priorityClassName: super-high-priority
      containers:
      - name: app
        image: nginx:alpine
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
EOF

echo "[BREAKING] Scenario 5f: Creating pod with affinity rules that conflict..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: affinity-conflict
  namespace: $NAMESPACE
  labels:
    scenario: "5f"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: affinity-conflict
  template:
    metadata:
      labels:
        app: affinity-conflict
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: affinity-conflict
            topologyKey: kubernetes.io/hostname
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                - non-existent-node
      containers:
      - name: app
        image: nginx:alpine
EOF

echo ""
echo "=============================================="
echo "  Scenario 5 Activated!"
echo "=============================================="
echo ""
echo "Issues Created:"
echo "  5a. Pod with restrictive security context"
echo "  5b. ServiceAccount without RBAC permissions"
echo "  5c. Pod with impossible node selector"
echo "  5d. Node tainted preventing scheduling"
echo "  5e. High priority pods disrupting others"
echo "  5f. Conflicting affinity/anti-affinity rules"
echo ""
echo "Troubleshooting Commands:"
echo "  kubectl get pods -n $NAMESPACE -o wide"
echo "  kubectl describe pod <pod-name> -n $NAMESPACE"
echo "  kubectl get nodes --show-labels"
echo "  kubectl describe node <node-name>"
echo "  kubectl get priorityclass"
echo "  kubectl auth can-i --list --as=system:serviceaccount:$NAMESPACE:restricted-sa"
echo "  kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
echo ""
echo "Node tainted: $NODE_NAME"
