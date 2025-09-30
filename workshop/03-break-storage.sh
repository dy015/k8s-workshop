#!/bin/bash
###############################################################################
# Scenario 3: Storage and StatefulSet Issues
# Concepts: PV/PVC, StatefulSets, storage classes, volume mounting
# Difficulty: Intermediate
###############################################################################

set -e

NAMESPACE="workshop-app"

echo "=============================================="
echo "  BREAKING SCENARIO 3"
echo "  Storage & StatefulSet Issues"
echo "=============================================="
echo ""

echo "[BREAKING] Scenario 3a: Deleting PVC while pod is using it..."
kubectl scale statefulset mysql -n $NAMESPACE --replicas=0
sleep 5
kubectl delete pvc mysql-pvc -n $NAMESPACE --force --grace-period=0 || true

echo "[BREAKING] Scenario 3b: Creating PVC with non-existent storage class..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: broken-pvc
  namespace: $NAMESPACE
  labels:
    scenario: "3b"
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: non-existent-storage-class
  resources:
    requests:
      storage: 5Gi
EOF

echo "[BREAKING] Scenario 3c: Breaking StatefulSet by changing serviceName..."
kubectl patch statefulset mysql -n $NAMESPACE -p '{"spec":{"serviceName":"wrong-service"}}'

echo "[BREAKING] Scenario 3d: Creating pod with wrong volume mount path..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: broken-mount
  namespace: $NAMESPACE
  labels:
    scenario: "3d"
spec:
  containers:
  - name: app
    image: nginx:alpine
    volumeMounts:
    - name: data
      mountPath: /nonexistent/path/that/will/fail
      subPath: missing/subdirectory
  volumes:
  - name: data
    emptyDir: {}
EOF

echo "[BREAKING] Scenario 3e: Creating PVC with insufficient storage..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: insufficient-storage
  namespace: $NAMESPACE
  labels:
    scenario: "3e"
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1000Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: large-storage-pod
  namespace: $NAMESPACE
spec:
  containers:
  - name: app
    image: nginx:alpine
    volumeMounts:
    - name: storage
      mountPath: /data
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: insufficient-storage
EOF

echo ""
echo "=============================================="
echo "  Scenario 3 Activated!"
echo "=============================================="
echo ""
echo "Issues Created:"
echo "  3a. Missing PVC for StatefulSet"
echo "  3b. PVC with non-existent storage class"
echo "  3c. StatefulSet with wrong serviceName"
echo "  3d. Pod with invalid volume mount"
echo "  3e. PVC requesting more storage than available"
echo ""
echo "Troubleshooting Commands:"
echo "  kubectl get pvc -n $NAMESPACE"
echo "  kubectl describe pvc <pvc-name> -n $NAMESPACE"
echo "  kubectl get pv"
echo "  kubectl get storageclass"
echo "  kubectl describe statefulset mysql -n $NAMESPACE"
echo "  kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
echo ""
