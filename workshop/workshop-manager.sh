#!/bin/bash
###############################################################################
# Kubernetes Workshop Manager
# Easily deploy, break, and reset workshop scenarios
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

NAMESPACE="workshop-app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║  Kubernetes Troubleshooting Workshop Manager         ║
║  Learn by Breaking Things!                            ║
╚═══════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

check_cluster() {
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        log_info "Please ensure kubectl is configured"
        exit 1
    fi
    log_success "Connected to Kubernetes cluster"
}

show_menu() {
    echo ""
    echo "What would you like to do?"
    echo ""
    echo "  ${GREEN}SETUP:${NC}"
    echo "    1) Deploy workshop application"
    echo "    2) Check application status"
    echo "    3) Test application"
    echo ""
    echo "  ${YELLOW}SCENARIOS:${NC}"
    echo "    4) Scenario 1: Pod Issues (Beginner)"
    echo "    5) Scenario 2: Networking (Intermediate)"
    echo "    6) Scenario 3: Storage (Intermediate)"
    echo "    7) Scenario 4: Configuration (Intermediate)"
    echo "    8) Scenario 5: RBAC & Nodes (Advanced)"
    echo ""
    echo "  ${CYAN}UTILITIES:${NC}"
    echo "    9) Clean up broken resources"
    echo "   10) Reset application"
    echo "   11) View troubleshooting guide"
    echo "   12) Show useful commands"
    echo ""
    echo "  ${RED}CLEANUP:${NC}"
    echo "   13) Complete cleanup (remove everything)"
    echo ""
    echo "    0) Exit"
    echo ""
}

deploy_app() {
    log_info "Deploying workshop application..."
    if [[ -f "$SCRIPT_DIR/00-deploy-app.sh" ]]; then
        bash "$SCRIPT_DIR/00-deploy-app.sh"
    else
        log_error "Deploy script not found: $SCRIPT_DIR/00-deploy-app.sh"
        exit 1
    fi
}

check_status() {
    log_info "Checking application status..."
    echo ""
    
    log_info "Namespace: $NAMESPACE"
    kubectl get namespace $NAMESPACE &> /dev/null || {
        log_error "Namespace $NAMESPACE does not exist"
        log_info "Run option 1 to deploy the application first"
        return 1
    }
    
    echo ""
    log_info "Pods:"
    kubectl get pods -n $NAMESPACE -o wide
    
    echo ""
    log_info "Services:"
    kubectl get svc -n $NAMESPACE
    
    echo ""
    log_info "Deployments:"
    kubectl get deployment -n $NAMESPACE
    
    echo ""
    log_info "StatefulSets:"
    kubectl get statefulset -n $NAMESPACE
    
    echo ""
    log_info "PVCs:"
    kubectl get pvc -n $NAMESPACE
    
    echo ""
    log_info "Recent Events:"
    kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -10
}

test_app() {
    log_info "Testing application..."
    
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    
    echo ""
    log_info "Frontend Health Check:"
    if curl -s -f "http://${NODE_IP}:30080/health" > /dev/null 2>&1; then
        log_success "✓ Frontend is healthy"
        curl -s "http://${NODE_IP}:30080/health"
    else
        log_error "✗ Frontend health check failed"
    fi
    
    echo ""
    log_info "Backend API Test:"
    if curl -s -f "http://${NODE_IP}:30080/api" > /dev/null 2>&1; then
        log_success "✓ Backend is responding"
        curl -s "http://${NODE_IP}:30080/api"
    else
        log_error "✗ Backend is not responding"
    fi
    
    echo ""
    log_info "Access URLs:"
    echo "  Frontend: http://${NODE_IP}:30080"
    echo "  Backend API: http://${NODE_IP}:30080/api"
    echo "  Health Check: http://${NODE_IP}:30080/health"
}

run_scenario() {
    local scenario=$1
    local script_name=$2
    local title=$3
    
    echo ""
    log_warning "================================================"
    log_warning "  Running: $title"
    log_warning "================================================"
    echo ""
    
    if [[ ! -f "$SCRIPT_DIR/$script_name" ]]; then
        log_error "Script not found: $SCRIPT_DIR/$script_name"
        return 1
    fi
    
    read -p "This will break things in the cluster. Continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Cancelled"
        return 0
    fi
    
    bash "$SCRIPT_DIR/$script_name"
    
    echo ""
    log_info "================================================"
    log_success "Scenario activated!"
    log_info "================================================"
    echo ""
    log_info "Next steps:"
    echo "  1. Investigate the issues:"
    echo "     kubectl get pods -n $NAMESPACE"
    echo "     kubectl describe pod <pod-name> -n $NAMESPACE"
    echo "  2. Check the troubleshooting guide (option 11)"
    echo "  3. Try to fix the issues"
    echo "  4. Clean up broken resources (option 9)"
    echo ""
}

clean_broken() {
    log_info "Cleaning up broken resources..."
    
    log_info "Removing pods with scenario label..."
    kubectl delete pod -l scenario -n $NAMESPACE 2>/dev/null || true
    
    log_info "Removing deployments with scenario label..."
    kubectl delete deployment -l scenario -n $NAMESPACE 2>/dev/null || true
    
    log_info "Removing services with scenario label..."
    kubectl delete svc -l scenario -n $NAMESPACE 2>/dev/null || true
    
    log_info "Removing PVCs with scenario label..."
    kubectl delete pvc -l scenario -n $NAMESPACE 2>/dev/null || true
    
    log_info "Removing NetworkPolicies..."
    kubectl delete networkpolicy deny-all -n $NAMESPACE 2>/dev/null || true
    
    log_info "Removing PriorityClasses..."
    kubectl delete priorityclass super-high-priority 2>/dev/null || true
    
    log_info "Removing node taints..."
    NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
    kubectl taint nodes $NODE_NAME workshop- 2>/dev/null || true
    
    log_success "Cleanup completed"
    
    echo ""
    log_info "You may want to reset core components:"
    echo "  - Backend ConfigMap: kubectl apply -f <config>"
    echo "  - MySQL Secret: kubectl apply -f <secret>"
    echo "  - NetworkPolicies: kubectl apply -f <netpol>"
    echo ""
    log_info "Or use option 10 to completely reset the application"
}

reset_app() {
    log_warning "This will delete and redeploy the entire application"
    read -p "Continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Cancelled"
        return 0
    fi
    
    log_info "Deleting namespace..."
    kubectl delete namespace $NAMESPACE --timeout=60s 2>/dev/null || true
    
    log_info "Waiting for namespace to be fully deleted..."
    while kubectl get namespace $NAMESPACE &> /dev/null; do
        echo -n "."
        sleep 2
    done
    echo ""
    
    log_info "Redeploying application..."
    deploy_app
}

view_guide() {
    if [[ -f "$SCRIPT_DIR/../TROUBLESHOOTING-GUIDE.md" ]]; then
        if command -v less &> /dev/null; then
            less "$SCRIPT_DIR/../TROUBLESHOOTING-GUIDE.md"
        elif command -v more &> /dev/null; then
            more "$SCRIPT_DIR/../TROUBLESHOOTING-GUIDE.md"
        else
            cat "$SCRIPT_DIR/../TROUBLESHOOTING-GUIDE.md"
        fi
    else
        log_error "Troubleshooting guide not found"
        log_info "Expected location: $SCRIPT_DIR/../TROUBLESHOOTING-GUIDE.md"
    fi
}

show_commands() {
    echo ""
    log_info "Essential Troubleshooting Commands"
    echo ""
    
    cat << 'EOF'
POD TROUBLESHOOTING:
  kubectl get pods -n workshop-app -o wide
  kubectl describe pod <pod-name> -n workshop-app
  kubectl logs <pod-name> -n workshop-app
  kubectl logs <pod-name> -n workshop-app --previous
  kubectl exec -it <pod-name> -n workshop-app -- sh

EVENTS (MOST USEFUL!):
  kubectl get events -n workshop-app --sort-by='.lastTimestamp'
  kubectl get events -n workshop-app --watch

SERVICES & NETWORKING:
  kubectl get svc,endpoints -n workshop-app
  kubectl describe svc <service-name> -n workshop-app
  kubectl exec -it <pod> -n workshop-app -- curl <service>:3000
  kubectl exec -it <pod> -n workshop-app -- nslookup <service>

STORAGE:
  kubectl get pv,pvc -n workshop-app
  kubectl describe pvc <pvc-name> -n workshop-app
  kubectl get storageclass

CONFIGURATION:
  kubectl get configmap,secret -n workshop-app
  kubectl describe configmap <name> -n workshop-app
  kubectl get secret <name> -n workshop-app -o yaml

RBAC:
  kubectl get sa,role,rolebinding -n workshop-app
  kubectl auth can-i <verb> <resource> --as=<user> -n workshop-app

NODES:
  kubectl get nodes --show-labels
  kubectl describe node <node-name>
  kubectl top nodes

RESOURCE USAGE:
  kubectl top pods -n workshop-app

DEBUG POD:
  kubectl run debug --image=busybox --rm -it --restart=Never -- sh
EOF
    echo ""
}

complete_cleanup() {
    log_warning "================================================"
    log_warning "  COMPLETE CLEANUP"
    log_warning "  This will remove EVERYTHING"
    log_warning "================================================"
    echo ""
    echo "This will delete:"
    echo "  - workshop-app namespace"
    echo "  - All workshop resources"
    echo "  - Priority classes"
    echo "  - Node taints"
    echo ""
    
    read -p "Are you absolutely sure? (type 'DELETE' to confirm): " confirm
    if [[ "$confirm" != "DELETE" ]]; then
        log_info "Cancelled"
        return 0
    fi
    
    log_info "Deleting namespace..."
    kubectl delete namespace $NAMESPACE 2>/dev/null || true
    
    log_info "Removing priority classes..."
    kubectl delete priorityclass super-high-priority 2>/dev/null || true
    
    log_info "Removing node taints..."
    NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
    kubectl taint nodes $NODE_NAME workshop- 2>/dev/null || true
    
    log_info "Restoring CoreDNS..."
    if [[ -f /tmp/coredns-backup.yaml ]]; then
        kubectl apply -f /tmp/coredns-backup.yaml 2>/dev/null || true
        kubectl rollout restart deployment coredns -n kube-system
    fi
    
    log_success "Complete cleanup finished"
    echo ""
    log_info "The workshop environment has been removed"
    log_info "Run option 1 to deploy again"
}

main() {
    show_banner
    check_cluster
    
    while true; do
        show_menu
        read -p "Enter your choice (0-13): " choice
        
        case $choice in
            1)
                deploy_app
                ;;
            2)
                check_status
                ;;
            3)
                test_app
                ;;
            4)
                run_scenario 1 "01-break-pods.sh" "Scenario 1: Pod Issues"
                ;;
            5)
                run_scenario 2 "02-break-networking.sh" "Scenario 2: Networking"
                ;;
            6)
                run_scenario 3 "03-break-storage.sh" "Scenario 3: Storage"
                ;;
            7)
                run_scenario 4 "04-break-config.sh" "Scenario 4: Configuration"
                ;;
            8)
                run_scenario 5 "05-break-rbac-nodes.sh" "Scenario 5: RBAC & Nodes"
                ;;
            9)
                clean_broken
                ;;
            10)
                reset_app
                ;;
            11)
                view_guide
                ;;
            12)
                show_commands
                ;;
            13)
                complete_cleanup
                ;;
            0)
                log_info "Exiting workshop manager"
                exit 0
                ;;
            *)
                log_error "Invalid choice. Please enter 0-13"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

main "$@"
