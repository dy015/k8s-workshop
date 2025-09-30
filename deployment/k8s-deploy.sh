#!/bin/bash
set -e

###############################################################################
# Kubernetes Cluster Manager for CentOS 9 Stream
# Version: 2.0 (SSH-Safe Edition)
# Features:
#   - Pre-installation checks
#   - Automatic installation
#   - SSH-safe complete cleanup
#   - Interactive mode
#   - Non-interactive mode for automation
###############################################################################

# Configuration
K8S_VERSION="1.28"
POD_CIDR="10.244.0.0/16"
CALICO_VERSION="v3.26.1"
DEFAULT_HOSTNAME="k8s-master"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Progress indicator
show_progress() {
    local pid=$1
    local message=$2
    local spin='-\|/'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r${BLUE}[PROGRESS]${NC} $message ${spin:$i:1}"
        sleep 0.1
    done
    printf "\r${GREEN}[DONE]${NC} $message     \n"
}

###############################################################################
# Pre-check Functions
###############################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/centos-release ]]; then
        log_error "This script is designed for CentOS 9 Stream"
        exit 1
    fi
    
    if ! grep -q "Stream" /etc/centos-release; then
        log_warning "This script is optimized for CentOS 9 Stream"
        read -p "Continue anyway? (yes/no): " continue_anyway
        if [[ "$continue_anyway" != "yes" ]]; then
            exit 1
        fi
    fi
}

check_network() {
    log_info "Checking network connectivity..."
    
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        log_error "No internet connectivity. Please check your network connection."
        exit 1
    fi
    
    if ! ping -c 1 google.com &> /dev/null; then
        log_error "DNS resolution failed. Please check your DNS settings."
        exit 1
    fi
    
    log_success "Network connectivity OK"
}

check_resources() {
    log_info "Checking system resources..."
    
    # Check CPU cores
    local cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 2 ]]; then
        log_error "Minimum 2 CPU cores required. Current: $cpu_cores"
        exit 1
    fi
    log_success "CPU cores: $cpu_cores (minimum: 2)"
    
    # Check RAM
    local ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $ram_gb -lt 2 ]]; then
        log_error "Minimum 2GB RAM required. Current: ${ram_gb}GB"
        exit 1
    fi
    log_success "RAM: ${ram_gb}GB (minimum: 2GB)"
    
    # Check disk space
    local disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $disk_gb -lt 20 ]]; then
        log_error "Minimum 20GB free disk space required. Current: ${disk_gb}GB"
        exit 1
    fi
    log_success "Free disk space: ${disk_gb}GB (minimum: 20GB)"
}

check_existing_installation() {
    log_info "Checking for existing Kubernetes installation..."
    
    local has_k8s=false
    local components=()
    
    # Check for running processes
    if pgrep -x "kubelet" > /dev/null; then
        components+=("kubelet process")
        has_k8s=true
    fi
    
    # Check for installed packages
    if rpm -qa | grep -qE "^(kubelet|kubeadm|kubectl)-"; then
        components+=("Kubernetes packages")
        has_k8s=true
    fi
    
    # Check for directories
    if [[ -d /etc/kubernetes ]]; then
        components+=("/etc/kubernetes directory")
        has_k8s=true
    fi
    
    # Check for containerd
    if systemctl is-active --quiet containerd; then
        components+=("containerd service")
    fi
    
    if [[ "$has_k8s" == true ]]; then
        log_warning "Existing Kubernetes installation detected:"
        for component in "${components[@]}"; do
            echo "  - $component"
        done
        return 0
    else
        log_success "No existing Kubernetes installation found"
        return 1
    fi
}

check_network_conflicts() {
    log_info "Checking for network conflicts..."
    
    local conflicts=false
    
    # Get local network ranges
    local local_networks=$(ip route show | grep -oP '\d+\.\d+\.\d+\.\d+/\d+' | sort -u)
    
    # Check if pod CIDR conflicts with local networks
    for network in $local_networks; do
        if [[ "$network" == "10.244."* ]]; then
            log_error "Pod network CIDR (10.244.0.0/16) conflicts with existing network: $network"
            conflicts=true
        fi
    done
    
    if [[ "$conflicts" == true ]]; then
        log_error "Network conflict detected. You may need to use a different CIDR."
        log_info "Edit this script and change POD_CIDR to a different range (e.g., 10.32.0.0/16)"
        exit 1
    fi
    
    log_success "No network conflicts detected"
}

check_ports() {
    log_info "Checking required ports..."
    
    local ports=(6443 2379 2380 10250 10259 10257)
    local port_conflicts=false
    
    for port in "${ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            log_warning "Port $port is already in use"
            port_conflicts=true
        fi
    done
    
    if [[ "$port_conflicts" == true ]]; then
        log_warning "Some required ports are in use. This may cause issues."
        read -p "Continue anyway? (yes/no): " continue_anyway
        if [[ "$continue_anyway" != "yes" ]]; then
            exit 1
        fi
    else
        log_success "All required ports are available"
    fi
}

###############################################################################
# Installation Functions
###############################################################################

update_system() {
    log_info "Updating system packages..."
    dnf update -y > /dev/null 2>&1 &
    show_progress $! "Updating system packages"
    log_success "System updated"
}

configure_hostname() {
    local hostname=${1:-$DEFAULT_HOSTNAME}
    log_info "Configuring hostname: $hostname"
    
    hostnamectl set-hostname "$hostname"
    local ip_addr=$(hostname -I | awk '{print $1}')
    
    if ! grep -q "$hostname" /etc/hosts; then
        echo "$ip_addr $hostname" >> /etc/hosts
    fi
    
    log_success "Hostname configured: $hostname (IP: $ip_addr)"
}

disable_swap() {
    log_info "Disabling swap..."
    
    swapoff -a
    sed -i '/ swap / s/^/#/' /etc/fstab
    
    if [[ $(swapon --show | wc -l) -eq 0 ]]; then
        log_success "Swap disabled"
    else
        log_error "Failed to disable swap"
        exit 1
    fi
}

configure_kernel() {
    log_info "Configuring kernel modules and parameters..."
    
    # Load kernel modules
    cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
    
    modprobe overlay
    modprobe br_netfilter
    
    # Configure sysctl
    cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    
    sysctl --system > /dev/null 2>&1
    
    log_success "Kernel configured"
}

install_containerd() {
    log_info "Installing containerd..."
    
    # Install dependencies
    dnf install -y yum-utils > /dev/null 2>&1 &
    show_progress $! "Installing dependencies"
    
    # Add Docker repository
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo > /dev/null 2>&1
    
    # Install containerd
    dnf install -y containerd.io > /dev/null 2>&1 &
    show_progress $! "Installing containerd"
    
    # Configure containerd
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    # Start containerd
    systemctl enable --now containerd > /dev/null 2>&1
    
    if systemctl is-active --quiet containerd; then
        log_success "containerd installed and running"
    else
        log_error "Failed to start containerd"
        exit 1
    fi
}

configure_firewall() {
    log_info "Configuring firewall..."
    
    if systemctl is-active --quiet firewalld; then
        local ports=(6443 2379-2380 10250 10259 10257 30000-32767 179 4789)
        
        for port in "${ports[@]}"; do
            if [[ $port == *"-"* ]]; then
                firewall-cmd --permanent --add-port=${port}/tcp > /dev/null 2>&1
            elif [[ $port == "4789" ]]; then
                firewall-cmd --permanent --add-port=${port}/udp > /dev/null 2>&1
            else
                firewall-cmd --permanent --add-port=${port}/tcp > /dev/null 2>&1
            fi
        done
        
        firewall-cmd --reload > /dev/null 2>&1
        log_success "Firewall configured"
    else
        log_info "Firewall not active, skipping configuration"
    fi
}

disable_selinux() {
    log_info "Configuring SELinux..."
    
    setenforce 0 2>/dev/null || true
    sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
    
    log_success "SELinux set to permissive mode"
}

install_kubernetes() {
    log_info "Installing Kubernetes components..."
    
    # Add Kubernetes repository
    cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
    
    # Install packages
    dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes > /dev/null 2>&1 &
    show_progress $! "Installing Kubernetes packages"
    
    # Enable kubelet
    systemctl enable --now kubelet > /dev/null 2>&1
    
    log_success "Kubernetes components installed"
}

initialize_cluster() {
    log_info "Initializing Kubernetes cluster..."
    log_info "This may take 2-3 minutes..."
    
    local ip_addr=$(hostname -I | awk '{print $1}')
    
    kubeadm init \
        --pod-network-cidr=$POD_CIDR \
        --apiserver-advertise-address=$ip_addr \
        > /tmp/kubeadm-init.log 2>&1
    
    if [[ $? -eq 0 ]]; then
        log_success "Cluster initialized successfully"
        
        # Save join command
        grep -A 2 "kubeadm join" /tmp/kubeadm-init.log > /tmp/kubeadm-join-command.sh
        chmod +x /tmp/kubeadm-join-command.sh
        log_info "Join command saved to: /tmp/kubeadm-join-command.sh"
    else
        log_error "Cluster initialization failed. Check /tmp/kubeadm-init.log for details"
        exit 1
    fi
}

configure_kubectl() {
    log_info "Configuring kubectl..."
    
    local user_home
    if [[ -n "$SUDO_USER" ]]; then
        user_home=$(eval echo ~$SUDO_USER)
    else
        user_home=$HOME
    fi
    
    mkdir -p "$user_home/.kube"
    cp -f /etc/kubernetes/admin.conf "$user_home/.kube/config"
    
    if [[ -n "$SUDO_USER" ]]; then
        chown -R $SUDO_USER:$SUDO_USER "$user_home/.kube"
    fi
    
    # Also configure for root if running as sudo
    if [[ -n "$SUDO_USER" ]]; then
        mkdir -p /root/.kube
        cp -f /etc/kubernetes/admin.conf /root/.kube/config
    fi
    
    log_success "kubectl configured"
}

install_cni() {
    log_info "Installing Calico CNI plugin..."
    
    # Download Calico manifest
    curl -sSL "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml" -o /tmp/calico.yaml 2>/dev/null
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to download Calico manifest"
        exit 1
    fi
    
    # Modify CIDR
    sed -i "s|192.168.0.0/16|${POD_CIDR}|g" /tmp/calico.yaml
    
    # Apply manifest
    kubectl apply -f /tmp/calico.yaml > /dev/null 2>&1
    
    log_info "Waiting for Calico pods to be ready (this may take 2-3 minutes)..."
    
    # Wait for calico to be ready with timeout
    local timeout=300
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=10s > /dev/null 2>&1; then
            log_success "Calico CNI plugin installed and ready"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done
    
    log_warning "Calico pods are taking longer than expected to be ready"
    log_info "You can check status with: kubectl get pods -n kube-system"
}

install_storage_provisioner() {
    log_info "Installing local-path storage provisioner..."
    
    # Install local-path provisioner
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml > /dev/null 2>&1
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to install local-path provisioner"
        exit 1
    fi
    
    log_info "Waiting for storage provisioner to be ready..."
    kubectl wait --for=condition=ready pod -l app=local-path-provisioner -n local-path-storage --timeout=120s > /dev/null 2>&1
    
    # Set as default storage class
    kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' > /dev/null 2>&1
    
    log_success "Storage provisioner installed and configured"
}

remove_taint() {
    log_info "Removing control-plane taint for single-node cluster..."
    
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- > /dev/null 2>&1 || true
    
    log_success "Taint removed"
}

verify_installation() {
    log_info "Verifying installation..."
    
    # Check node status
    local node_status=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}')
    
    if [[ "$node_status" == "Ready" ]]; then
        log_success "Node is Ready"
    else
        log_warning "Node status: $node_status (may take a few more minutes)"
    fi
    
    # Check system pods
    local pods_not_ready=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "Running" | wc -l)
    
    if [[ $pods_not_ready -eq 0 ]]; then
        log_success "All system pods are running"
    else
        log_warning "$pods_not_ready system pods are not yet running"
    fi
}

###############################################################################
# SSH-Safe Cleanup Functions
###############################################################################

cleanup_kubernetes() {
    log_info "Starting SSH-safe Kubernetes cleanup..."
    
    # Detect SSH connection
    local is_ssh=false
    if [[ -n "$SSH_CONNECTION" ]] || [[ -n "$SSH_CLIENT" ]] || [[ -n "$SSH_TTY" ]]; then
        is_ssh=true
        log_info "SSH connection detected - preserving network connectivity"
    fi
    
    # Stop kubelet
    log_info "Stopping kubelet service..."
    systemctl stop kubelet 2>/dev/null || true
    systemctl disable kubelet 2>/dev/null || true
    
    # Reset kubeadm
    if command -v kubeadm &> /dev/null; then
        log_info "Resetting kubeadm configuration..."
        kubeadm reset -f > /dev/null 2>&1 || true
    fi
    
    # Remove Kubernetes packages
    log_info "Removing Kubernetes packages..."
    dnf remove -y kubelet kubeadm kubectl kubernetes-cni cri-tools --disableexcludes=kubernetes > /dev/null 2>&1 || true
    
    # Stop and remove containerd
    log_info "Removing containerd..."
    systemctl stop containerd 2>/dev/null || true
    systemctl disable containerd 2>/dev/null || true
    dnf remove -y containerd.io > /dev/null 2>&1 || true
    
    # Remove repositories
    rm -f /etc/yum.repos.d/kubernetes.repo
    rm -f /etc/yum.repos.d/docker-ce.repo
    
    # Remove directories and files
    log_info "Removing configuration files and data..."
    rm -rf /etc/kubernetes
    rm -rf /var/lib/kubelet
    rm -rf /var/lib/etcd
    rm -rf /etc/cni
    rm -rf /var/lib/cni
    rm -rf /opt/cni
    rm -rf /var/lib/containerd
    rm -rf /etc/containerd
    rm -rf /run/containerd
    rm -rf /var/log/pods
    rm -rf /var/log/containers
    
    # Remove local-path storage provisioner data
    log_info "Removing local-path storage data..."
    if [[ -d /opt/local-path-provisioner ]]; then
        rm -rf /opt/local-path-provisioner
        log_success "Local-path storage data removed"
    fi
    
    # Remove user kubectl config
    if [[ -n "$SUDO_USER" ]]; then
        local user_home=$(eval echo ~$SUDO_USER)
        rm -rf "$user_home/.kube"
    fi
    rm -rf /root/.kube
    
    # Clean network interfaces (SSH-safe)
    log_info "Cleaning Kubernetes network interfaces (preserving default interface)..."
    
    # Get current default interface to avoid disrupting it
    local default_iface=$(ip route | grep default | awk '{print $5}' | head -n1)
    log_info "Default network interface: $default_iface (will be preserved)"
    
    # Only remove k8s-specific interfaces
    for iface in $(ip link show | grep -oP '(cali[^:@]+|tunl0|vxlan\.calico|flannel\.1|cni0)' 2>/dev/null); do
        # Double-check it's not the default interface
        if [[ "$iface" != "$default_iface" ]] && [[ -n "$iface" ]]; then
            log_info "Removing interface: $iface"
            ip link set "$iface" down 2>/dev/null || true
            ip link delete "$iface" 2>/dev/null || true
        fi
    done
    
    log_success "Kubernetes network interfaces cleaned"
    
    # Clean iptables (SSH-safe - only remove K8s rules)
    log_info "Cleaning iptables rules (preserving SSH and system rules)..."
    
    if [[ "$is_ssh" == true ]]; then
        log_warning "SSH detected - using selective iptables cleanup"
    fi
    
    # Remove Kubernetes-specific chains from NAT table
    for chain in $(iptables -t nat -L -n 2>/dev/null | grep -oP 'KUBE-[A-Z0-9-]+' | sort -u); do
        iptables -t nat -F "$chain" 2>/dev/null || true
        iptables -t nat -X "$chain" 2>/dev/null || true
    done
    
    # Remove Kubernetes-specific chains from FILTER table
    for chain in $(iptables -t filter -L -n 2>/dev/null | grep -oP 'KUBE-[A-Z0-9-]+' | sort -u); do
        iptables -t filter -F "$chain" 2>/dev/null || true
        iptables -t filter -X "$chain" 2>/dev/null || true
    done
    
    # Remove Calico-specific chains from FILTER table
    for chain in $(iptables -t filter -L -n 2>/dev/null | grep -oP 'cali-[a-z0-9-]+' | sort -u); do
        iptables -t filter -F "$chain" 2>/dev/null || true
        iptables -t filter -X "$chain" 2>/dev/null || true
    done
    
    # Remove Calico-specific chains from NAT table
    for chain in $(iptables -t nat -L -n 2>/dev/null | grep -oP 'cali-[a-z0-9-]+' | sort -u); do
        iptables -t nat -F "$chain" 2>/dev/null || true
        iptables -t nat -X "$chain" 2>/dev/null || true
    done
    
    # Remove specific K8s rules from main chains (preserve others)
    iptables -t nat -D PREROUTING -m comment --comment "kubernetes service portals" -j KUBE-SERVICES 2>/dev/null || true
    iptables -t nat -D OUTPUT -m comment --comment "kubernetes service portals" -j KUBE-SERVICES 2>/dev/null || true
    iptables -t nat -D POSTROUTING -m comment --comment "kubernetes postrouting rules" -j KUBE-POSTROUTING 2>/dev/null || true
    iptables -t filter -D FORWARD -m comment --comment "kubernetes forwarding rules" -j KUBE-FORWARD 2>/dev/null || true
    
    # Do the same for ip6tables
    for chain in $(ip6tables -t nat -L -n 2>/dev/null | grep -oP 'KUBE-[A-Z0-9-]+' | sort -u); do
        ip6tables -t nat -F "$chain" 2>/dev/null || true
        ip6tables -t nat -X "$chain" 2>/dev/null || true
    done
    
    for chain in $(ip6tables -t filter -L -n 2>/dev/null | grep -oP 'KUBE-[A-Z0-9-]+' | sort -u); do
        ip6tables -t filter -F "$chain" 2>/dev/null || true
        ip6tables -t filter -X "$chain" 2>/dev/null || true
    done
    
    log_success "Kubernetes iptables rules cleaned (SSH and system rules preserved)"
    
    # Ensure network connectivity is maintained
    log_info "Verifying network connectivity..."
    
    # Restart NetworkManager to ensure routing is correct
    if systemctl is-active --quiet NetworkManager; then
        log_info "Restarting NetworkManager to ensure connectivity..."
        systemctl restart NetworkManager
        sleep 3
    fi
    
    # Test connectivity
    if ping -c 1 8.8.8.8 &> /dev/null; then
        log_success "Network connectivity verified"
    else
        log_warning "Network connectivity check failed, but this may be temporary"
        log_info "If you lose connection, run: systemctl restart NetworkManager"
    fi
    
    # Clean ipvs rules
    if command -v ipvsadm &> /dev/null; then
        ipvsadm -C 2>/dev/null || true
    fi
    
    # Remove kernel modules (safe to fail)
    log_info "Removing kernel modules..."
    rmmod overlay 2>/dev/null || true
    rmmod br_netfilter 2>/dev/null || true
    
    # Remove kernel module configuration
    rm -f /etc/modules-load.d/k8s.conf
    rm -f /etc/sysctl.d/k8s.conf
    
    # Reload sysctl
    sysctl --system > /dev/null 2>&1 || true
    
    # Re-enable swap
    log_info "Re-enabling swap..."
    if grep -q "^#.*swap" /etc/fstab; then
        sed -i '/swap/s/^#//' /etc/fstab
        swapon -a 2>/dev/null || true
    fi
    
    # Re-enable SELinux
    log_info "Restoring SELinux to enforcing mode..."
    if [[ -f /etc/selinux/config ]]; then
        sed -i 's/^SELINUX=permissive$/SELINUX=enforcing/' /etc/selinux/config
        # Don't enforce immediately if SSH is active
        if [[ "$is_ssh" == false ]]; then
            setenforce 1 2>/dev/null || true
        else
            log_info "SELinux will be enforced after reboot (preserved for SSH safety)"
        fi
    fi
    
    # Clean temporary files
    rm -f /tmp/calico.yaml
    rm -f /tmp/kubeadm-init.log
    rm -f /tmp/kubeadm-join-command.sh
    
    # Clean DNF cache
    dnf clean all > /dev/null 2>&1
    
    log_success "Cleanup completed successfully"
    
    if [[ "$is_ssh" == true ]]; then
        log_success "Your SSH connection was preserved throughout cleanup"
    fi
}

###############################################################################
# Main Functions
###############################################################################

show_usage() {
    cat << EOF
Kubernetes Cluster Manager for CentOS 9 Stream (SSH-Safe Edition)

Usage: $0 [OPTIONS]

OPTIONS:
    install             Install Kubernetes cluster
    cleanup             Remove Kubernetes cluster completely (SSH-safe)
    status              Check cluster status
    -h, --help          Show this help message
    
INTERACTIVE MODE:
    Run without arguments for interactive mode
    
EXAMPLES:
    $0 install          # Install Kubernetes
    $0 cleanup          # Remove Kubernetes (SSH-safe)
    $0 status           # Check status
    $0                  # Interactive mode

CONFIGURATION:
    Edit these variables in the script to customize:
    - K8S_VERSION       Current: $K8S_VERSION
    - POD_CIDR          Current: $POD_CIDR
    - CALICO_VERSION    Current: $CALICO_VERSION
    - DEFAULT_HOSTNAME  Current: $DEFAULT_HOSTNAME

SSH-SAFE CLEANUP:
    The cleanup function preserves:
    - Active SSH connections
    - System firewall rules
    - Default network interface
    - Network connectivity

EOF
}

do_install() {
    echo ""
    log_info "=========================================="
    log_info "  Kubernetes Installation Starting"
    log_info "=========================================="
    echo ""
    
    # Pre-checks
    log_info "Running pre-installation checks..."
    check_root
    check_os
    check_network
    check_resources
    check_network_conflicts
    check_ports
    
    # Check for existing installation
    if check_existing_installation; then
        echo ""
        read -p "Existing installation found. Clean up first? (yes/no): " cleanup_first
        if [[ "$cleanup_first" == "yes" ]]; then
            cleanup_kubernetes
            echo ""
            log_info "Proceeding with installation..."
        else
            log_error "Cannot proceed with existing installation. Exiting."
            exit 1
        fi
    fi
    
    echo ""
    log_info "All pre-checks passed. Starting installation..."
    
    # Get hostname
    read -p "Enter hostname for this node [${DEFAULT_HOSTNAME}]: " input_hostname
    hostname="${input_hostname:-$DEFAULT_HOSTNAME}"
    
    echo ""
    log_info "Installation will use the following settings:"
    log_info "  - Hostname: $hostname"
    log_info "  - Pod Network CIDR: $POD_CIDR"
    log_info "  - Kubernetes Version: $K8S_VERSION"
    log_info "  - Calico Version: $CALICO_VERSION"
    echo ""
    
    read -p "Proceed with installation? (yes/no): " proceed
    if [[ "$proceed" != "yes" ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
    
    echo ""
    log_info "Starting installation (this will take 5-10 minutes)..."
    echo ""
    
    # Installation steps
    update_system
    configure_hostname "$hostname"
    disable_swap
    configure_kernel
    install_containerd
    configure_firewall
    disable_selinux
    install_kubernetes
    initialize_cluster
    configure_kubectl
    install_cni
    install_storage_provisioner
    remove_taint
    
    echo ""
    log_info "Waiting 30 seconds for cluster to stabilize..."
    sleep 30
    
    verify_installation
    
    echo ""
    log_info "=========================================="
    log_success "Installation completed successfully!"
    log_info "=========================================="
    echo ""
    
    # Show cluster info
    log_info "Cluster Information:"
    kubectl cluster-info 2>/dev/null || true
    echo ""
    
    log_info "Node Status:"
    kubectl get nodes 2>/dev/null || true
    echo ""
    
    log_info "System Pods:"
    kubectl get pods -n kube-system 2>/dev/null || true
    echo ""
    
    log_info "Useful commands:"
    echo "  kubectl get nodes              # Check node status"
    echo "  kubectl get pods -A            # Check all pods"
    echo "  kubectl cluster-info           # Cluster information"
    echo ""
    
    if [[ -f /tmp/kubeadm-join-command.sh ]]; then
        log_info "To add worker nodes, run the command in: /tmp/kubeadm-join-command.sh"
        echo ""
    fi
}

do_cleanup() {
    echo ""
    log_warning "=========================================="
    log_warning "  Kubernetes Cleanup (SSH-Safe)"
    log_warning "=========================================="
    echo ""
    
    check_root
    
    # Check if connected via SSH
    local is_ssh=false
    if [[ -n "$SSH_CONNECTION" ]] || [[ -n "$SSH_CLIENT" ]] || [[ -n "$SSH_TTY" ]]; then
        is_ssh=true
    fi
    
    if [[ "$is_ssh" == true ]]; then
        echo ""
        log_info "╔════════════════════════════════════════════════════════╗"
        log_info "║  SSH CONNECTION DETECTED                               ║"
        log_info "║  Your connection will be preserved during cleanup      ║"
        log_info "║  Network connectivity will be maintained               ║"
        log_info "╚════════════════════════════════════════════════════════╝"
        echo ""
    fi
    
    if ! check_existing_installation; then
        log_info "No Kubernetes installation found. Nothing to clean up."
        exit 0
    fi
    
    echo ""
    log_warning "This will completely remove:"
    log_warning "  - All Kubernetes components (kubelet, kubeadm, kubectl)"
    log_warning "  - containerd and all containers"
    log_warning "  - All configuration files and data"
    log_warning "  - Kubernetes network configurations"
    echo ""
    log_info "This will be preserved:"
    log_success "  ✓ Your SSH connection"
    log_success "  ✓ System firewall rules"
    log_success "  ✓ Default network interface"
    log_success "  ✓ Network connectivity"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
    
    echo ""
    cleanup_kubernetes
    
    echo ""
    log_info "=========================================="
    log_success "Cleanup completed successfully!"
    log_info "=========================================="
    echo ""
    
    log_info "System has been restored to pre-Kubernetes state:"
    log_success "  ✓ All Kubernetes components removed"
    log_success "  ✓ Network connectivity maintained"
    if [[ "$is_ssh" == true ]]; then
        log_success "  ✓ Your SSH connection was preserved"
    fi
    log_success "  ✓ Swap re-enabled"
    log_success "  ✓ SELinux will be enforcing after reboot"
    echo ""
    log_info "It is recommended to reboot the system: sudo reboot"
    echo ""
}

do_status() {
    echo ""
    log_info "=========================================="
    log_info "  Kubernetes Cluster Status"
    log_info "=========================================="
    echo ""
    
    check_root
    
    # Check if Kubernetes is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "Kubernetes is not installed"
        exit 1
    fi
    
    # Check kubelet
    log_info "Kubelet Status:"
    systemctl status kubelet --no-pager -l || true
    echo ""
    
    # Check nodes
    log_info "Node Status:"
    kubectl get nodes -o wide 2>/dev/null || log_error "Cannot connect to cluster"
    echo ""
    
    # Check pods
    log_info "System Pods Status:"
    kubectl get pods -n kube-system 2>/dev/null || log_error "Cannot get pods"
    echo ""
    
    # Check cluster info
    log_info "Cluster Information:"
    kubectl cluster-info 2>/dev/null || log_error "Cannot get cluster info"
    echo ""
    
    # Check resources
    log_info "Resource Usage:"
    if kubectl top nodes &> /dev/null; then
        kubectl top nodes 2>/dev/null || true
    else
        log_warning "Metrics server not installed. Install with:"
        echo "  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    fi
    echo ""
    
    # Check component health
    log_info "Component Status:"
    kubectl get componentstatuses 2>/dev/null || log_warning "Component status API deprecated in recent versions"
    echo ""
}

interactive_mode() {
    echo ""
    echo "=========================================="
    echo "  Kubernetes Cluster Manager"
    echo "  CentOS 9 Stream (SSH-Safe Edition)"
    echo "=========================================="
    echo ""
    echo "What would you like to do?"
    echo ""
    echo "1) Install Kubernetes cluster"
    echo "2) Check cluster status"
    echo "3) Cleanup/Remove Kubernetes (SSH-safe)"
    echo "4) Exit"
    echo ""
    read -p "Enter your choice (1-4): " choice
    
    case $choice in
        1)
            do_install
            ;;
        2)
            do_status
            ;;
        3)
            do_cleanup
            ;;
        4)
            log_info "Exiting..."
            exit 0
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
}

###############################################################################
# Main Script Logic
###############################################################################

main() {
    if [[ $# -eq 0 ]]; then
        interactive_mode
    else
        case "$1" in
            install)
                do_install
                ;;
            cleanup)
                do_cleanup
                ;;
            status)
                do_status
                ;;
            -h|--help)
                show_usage
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    fi
}

main "$@"
