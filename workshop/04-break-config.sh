#!/bin/bash
###############################################################################
# Scenario 4: ConfigMap, Secrets, and Resource Management Issues
# Concepts: ConfigMaps, Secrets, resource limits, env vars, probes
# Difficulty: Intermediate
###############################################################################

set -e

NAMESPACE="workshop-app"

echo "=============================================="
echo "  BREAKING SCENARIO 4"
echo "  ConfigMap, Secrets & Resources Issues"
echo "=============================================="
echo ""

echo "[BREAKING] Scenario 4a: Deleting ConfigMap that pods depend on..."
kubectl delete configmap backend-config -n $NAMESPACE

echo "[BREAKING] Scenario 4b: Breaking secret by corrupting data..."
kubectl patch secret mysql-secret -n $NAMESPACE -p '{"data":{"password":"YnJva2VucGFzc3dvcmQ="}}'
kubectl rollout restart statefulset mysql -n $NAMESPACE

echo "[BREAKING] Scenario 4c: Creating pod with invalid environment variable reference..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: broken-env
  namespace: $NAMESPACE
  labels:
    scenario: "4c"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: broken-env
  template:
    metadata:
      labels:
        app: broken-env
    spec:
      containers:
      - name: app
        image: nginx:alpine
        env:
        - name: CONFIG_VALUE
          valueFrom:
            configMapKeyRef:
              name: non-existent-configmap
              key: non-existent-key
        - name: SECRET_VALUE
          valueFrom:
            secretKeyRef:
              name: non-existent-secret
              key: non-existent-key
EOF

echo "[BREAKING] Scenario 4d: Setting unrealistic resource limits..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resource-limited
  namespace: $NAMESPACE
  labels:
    scenario: "4d"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: resource-limited
  template:
    metadata:
      labels:
        app: resource-limited
    spec:
      containers:
      - name: app
        image: nginx:alpine
        resources:
          requests:
            memory: "10Gi"
            cpu: "8"
          limits:
            memory: "10Gi"
            cpu: "8"
EOF

echo "[BREAKING] Scenario 4e: Breaking liveness probe..."
kubectl patch deployment backend -n $NAMESPACE -p '{"spec":{"template":{"spec":{"containers":[{"name":"backend","livenessProbe":{"httpGet":{"path":"/nonexistent","port":3000},"initialDelaySeconds":5,"periodSeconds":5}}]}}}}'

echo "[BREAKING] Scenario 4f: Creating invalid readiness probe..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: broken-probe
  namespace: $NAMESPACE
  labels:
    scenario: "4f"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: broken-probe
  template:
    metadata:
      labels:
        app: broken-probe
    spec:
      containers:
      - name: app
        image: nginx:alpine
        readinessProbe:
          httpGet:
            path: /ready
            port: 9999
          initialDelaySeconds: 1
          periodSeconds: 2
          failureThreshold: 1
EOF

echo ""
echo "=============================================="
echo "  Scenario 4 Activated!"
echo "=============================================="
echo ""
echo "Issues Created:"
echo "  4a. Missing ConfigMap"
echo "  4b. Incorrect Secret data"
echo "  4c. Invalid environment variable references"
echo "  4d. Unrealistic resource requests"
echo "  4e. Broken liveness probe"
echo "  4f. Invalid readiness probe"
echo ""
echo "Troubleshooting Commands:"
echo "  kubectl get configmaps -n $NAMESPACE"
echo "  kubectl get secrets -n $NAMESPACE"
echo "  kubectl describe pod <pod-name> -n $NAMESPACE"
echo "  kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
echo "  kubectl top pods -n $NAMESPACE"
echo "  kubectl logs <pod-name> -n $NAMESPACE --previous"
echo ""
