#!/bin/bash

# Fiber vs Spring Boot Benchmark Setup Script
# This script sets up the entire benchmark environment on a Kind cluster or existing cluster (e.g., Hetzner k3s)

set -e

# Parse command line arguments
USE_HETZNER=false
FIBER_TAG="latest"
SPRINGBOOT_TAG="latest"

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --hetzner            Skip Kind cluster creation and use existing kubeconfig"
    echo "                       (for Hetzner k3s or other external clusters)"
    echo "  --fiber-tag TAG      Docker image tag for fiber-server (default: latest)"
    echo "  --springboot-tag TAG Docker image tag for springboot-server (default: latest)"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                            # Create local Kind cluster and deploy"
    echo "  $0 --hetzner                                  # Deploy to existing cluster (e.g., Hetzner k3s)"
    echo "  $0 --hetzner --fiber-tag pr-5                 # Deploy with fiber-server from PR #5"
    echo "  $0 --fiber-tag pr-5 --springboot-tag pr-5     # Deploy both from PR #5"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --hetzner)
            USE_HETZNER=true
            shift
            ;;
        --fiber-tag)
            FIBER_TAG="$2"
            shift 2
            ;;
        --springboot-tag)
            SPRINGBOOT_TAG="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "  Fiber vs Spring Boot Benchmark Setup"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Step 1: Set up cluster (Kind or use existing)
echo ""
if [ "$USE_HETZNER" = true ]; then
    echo "Step 1: Using existing cluster (Hetzner/external)..."
    echo "-----------------------------------------------------"
    print_status "Skipping Kind cluster creation (--hetzner mode)"
    print_status "Using existing kubeconfig context"
    
    # Verify kubectl can connect
    if ! kubectl cluster-info &>/dev/null; then
        print_error "Cannot connect to cluster. Please ensure:"
        echo "  - KUBECONFIG is set correctly, or"
        echo "  - kubeconfig file exists at ./kubeconfig (for hetzner-k3s)"
        echo ""
        echo "For Hetzner k3s, run:"
        echo "  export KUBECONFIG=./kubeconfig"
        exit 1
    fi
    
    print_status "Connected to cluster:"
    kubectl cluster-info | head -1
else
    echo "Step 1: Setting up Kind cluster..."
    echo "-----------------------------------"

    if kind get clusters 2>/dev/null | grep -q "fiber-vs-springboot"; then
        print_warning "Deleting existing fiber-vs-springboot cluster..."
        kind delete cluster --name fiber-vs-springboot
    fi

    print_status "Creating new Kind cluster with node pools..."
    kind create cluster --config kind-config.yaml
fi

print_status "Verifying nodes..."
kubectl get nodes --show-labels | grep -E "pool|NAME"

# Step 2: Add Helm repositories
echo ""
echo "Step 2: Adding Helm repositories..."
echo "------------------------------------"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update
print_status "Helm repositories updated"

# Step 3: Install monitoring stack
echo ""
echo "Step 3: Installing monitoring stack..."
echo "---------------------------------------"

print_status "Installing kube-prometheus-stack..."
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  -f monitoring-values.yaml \
  --wait --timeout 10m

print_status "Monitoring stack installed"

# Step 4: Install k6 operator
echo ""
echo "Step 4: Installing k6 operator..."
echo "----------------------------------"

print_status "Installing k6-operator..."
helm upgrade --install k6-operator grafana/k6-operator \
  -n k6-operator \
  --create-namespace \
  -f k6-values.yaml \
  --wait || print_warning "k6-operator already exists, skipping..."

print_status "k6 operator installed"

# Step 5: Deploy applications
echo ""
echo "Step 5: Deploying Fiber and Spring Boot servers..."
echo "---------------------------------------------------"

kubectl create namespace fiber-vs-springboot --dry-run=client -o yaml | kubectl apply -f -

print_status "Deploying applications (fiber-server:${FIBER_TAG}, springboot-server:${SPRINGBOOT_TAG})..."
sed \
  -e "s|ghcr.io/huseyinbabal/benchmarks/fiber-server:latest|ghcr.io/huseyinbabal/benchmarks/fiber-server:${FIBER_TAG}|g" \
  -e "s|ghcr.io/huseyinbabal/benchmarks/springboot-server:latest|ghcr.io/huseyinbabal/benchmarks/springboot-server:${SPRINGBOOT_TAG}|g" \
  k8s/deployments.yaml | kubectl apply -f -

print_status "Waiting for deployments to be ready..."
kubectl wait --for=condition=available deployment/fiber-server -n fiber-vs-springboot --timeout=120s
kubectl wait --for=condition=available deployment/springboot-server -n fiber-vs-springboot --timeout=120s

print_status "Applications deployed"
kubectl get pods -n fiber-vs-springboot -o wide

# Step 6: Apply Grafana dashboard
echo ""
echo "Step 6: Configuring Grafana dashboard..."
echo "-----------------------------------------"

kubectl apply -f k8s/dashboard-configmap.yaml
print_status "Grafana dashboard configured"

# Step 7: Create k6 test ConfigMaps
echo ""
echo "Step 7: Creating k6 test ConfigMaps..."
echo "---------------------------------------"

kubectl create configmap k6-test-fiber \
  --from-file=test.js=k6/test-fiber.js \
  -n fiber-vs-springboot \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap k6-test-springboot \
  --from-file=test.js=k6/test-springboot.js \
  -n fiber-vs-springboot \
  --dry-run=client -o yaml | kubectl apply -f -

print_status "k6 test ConfigMaps created"

# Summary
echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "Deployed images:"
echo "  fiber-server:      ghcr.io/huseyinbabal/benchmarks/fiber-server:${FIBER_TAG}"
echo "  springboot-server: ghcr.io/huseyinbabal/benchmarks/springboot-server:${SPRINGBOOT_TAG}"
echo ""
echo "Next steps:"
echo ""
echo "1. Access Grafana:"
echo "   kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
echo "   Open: http://localhost:3000"
echo "   Login: admin / prom-operator"
echo ""
echo "2. Run the benchmarks:"
echo "   ./run-benchmark.sh --run-id iteration-1"
echo "   # Or with auto-generated timestamp:"
echo "   ./run-benchmark.sh"
echo ""
echo "3. Watch the tests:"
echo "   kubectl get testruns -n fiber-vs-springboot -w"
echo ""
echo "4. View pod status:"
echo "   kubectl get pods -n fiber-vs-springboot -w"
echo ""
echo "5. In Grafana, navigate to 'Fiber vs Spring Boot Benchmark' dashboard"
echo ""
print_status "Happy benchmarking!"
