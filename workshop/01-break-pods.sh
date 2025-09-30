#!/bin/bash
###############################################################################
# Scenario 1: Pod CrashLoopBackOff and ImagePullBackOff
# Concepts: Pod lifecycle, container issues, image management, troubleshooting
# Difficulty: Beginner
###############################################################################

set -e

NAMESPACE="workshop-app"

echo "=============================================="
echo "  BREAKING SCENARIO 1"
echo "  Pod Crash Loop & Image Pull Issues"
echo "=============================================="
echo ""

echo "[BREAKING] Scenario 1a: Deploying pod with non-existent image..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: broken-image
  namespace: $NAMESPACE
  labels:
    scenario: "1a"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: broken-image
  template:
    metadata:
      labels:
        app: broken-image
    spec:
      containers:
      - name: app
        image: nonexistent/fake-image:v99.99.99
        ports:
        - containerPort: 8080
EOF

echo "[BREAKING] Scenario 1b: Deploying pod with wrong container command..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crash-loop
  namespace: $NAMESPACE
  labels:
    scenario: "1b"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: crash-loop
  template:
    metadata:
      labels:
        app: crash-loop
    spec:
      containers:
      - name: app
        image: busybox:latest
        command: ["/bin/sh"]
        args: ["-c", "exit 1"]
EOF

echo "[BREAKING] Scenario 1c: Deploying pod with OOMKilled (memory limit too low)..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oom-killed
  namespace: $NAMESPACE
  labels:
    scenario: "1c"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: oom-killed
  template:
    metadata:
      labels:
        app: oom-killed
    spec:
      containers:
      - name: app
        image: nginx:alpine
        resources:
          requests:
            memory: "10Mi"
          limits:
            memory: "10Mi"
EOF

echo ""
echo "=============================================="
echo "  Scenario 1 Activated!"
echo "=============================================="
echo ""
echo "Issues Created:"
echo "  1a. ImagePullBackOff - Non-existent image"
echo "  1b. CrashLoopBackOff - Container exits immediately"
echo "  1c. OOMKilled - Memory limit too low"
echo ""
echo "Troubleshooting Commands:"
echo "  kubectl get pods -n $NAMESPACE"
echo "  kubectl describe pod <pod-name> -n $NAMESPACE"
echo "  kubectl logs <pod-name> -n $NAMESPACE"
echo "  kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
echo ""
