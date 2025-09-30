#!/bin/bash
###############################################################################
# Scenario 2: Service Discovery and Networking Issues
# Concepts: Services, DNS, selectors, endpoints, NetworkPolicy
# Difficulty: Intermediate
###############################################################################

set -e

NAMESPACE="workshop-app"

echo "=============================================="
echo "  BREAKING SCENARIO 2"
echo "  Service Discovery & Networking Issues"
echo "=============================================="
echo ""

echo "[BREAKING] Scenario 2a: Breaking service selector..."
kubectl patch service backend -n $NAMESPACE -p '{"spec":{"selector":{"app":"wrong-label"}}}'

echo "[BREAKING] Scenario 2b: Creating service with wrong port..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: broken-service
  namespace: $NAMESPACE
  labels:
    scenario: "2b"
spec:
  type: ClusterIP
  ports:
    - port: 9999
      targetPort: 8888
  selector:
    app: backend
EOF

echo "[BREAKING] Scenario 2c: Breaking DNS by corrupting CoreDNS config..."
kubectl get configmap coredns -n kube-system -o yaml > /tmp/coredns-backup.yaml
kubectl patch configmap coredns -n kube-system --type merge -p '{"data":{"Corefile":".:53 {\n    errors\n    health\n    loop\n    forward . 1.2.3.4\n}\n"}}'
kubectl rollout restart deployment coredns -n kube-system

echo "[BREAKING] Scenario 2d: Creating overly restrictive NetworkPolicy..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: $NAMESPACE
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

echo "[BREAKING] Scenario 2e: Breaking frontend service type..."
kubectl patch service frontend -n $NAMESPACE -p '{"spec":{"type":"ClusterIP"}}'

echo ""
echo "=============================================="
echo "  Scenario 2 Activated!"
echo "=============================================="
echo ""
echo "Issues Created:"
echo "  2a. Backend service selector mismatch"
echo "  2b. Service with wrong ports"
echo "  2c. CoreDNS misconfiguration"
echo "  2d. Overly restrictive NetworkPolicy"
echo "  2e. Frontend service type changed from NodePort"
echo ""
echo "Troubleshooting Commands:"
echo "  kubectl get svc -n $NAMESPACE"
echo "  kubectl get endpoints -n $NAMESPACE"
echo "  kubectl describe svc backend -n $NAMESPACE"
echo "  kubectl exec -it <frontend-pod> -n $NAMESPACE -- curl backend:3000"
echo "  kubectl get networkpolicies -n $NAMESPACE"
echo "  kubectl logs -n kube-system -l k8s-app=kube-dns"
echo ""
