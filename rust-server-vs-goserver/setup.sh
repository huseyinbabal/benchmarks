#!/bin/bash

# Go vs Rust Benchmark Setup Script
# This script sets up the entire benchmark environment on a Kind cluster or existing cluster (e.g., Hetzner k3s)

set -e

# Parse command line arguments
USE_HETZNER=false
GO_TAG="latest"
RUST_TAG="latest"

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --hetzner        Skip Kind cluster creation and use existing kubeconfig"
    echo "                   (for Hetzner k3s or other external clusters)"
    echo "  --go-tag TAG     Docker image tag for go-server (default: latest)"
    echo "  --rust-tag TAG   Docker image tag for rust-server (default: latest)"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Create local Kind cluster and deploy"
    echo "  $0 --hetzner                          # Deploy to existing cluster (e.g., Hetzner k3s)"
    echo "  $0 --hetzner --go-tag pr-5            # Deploy with go-server from PR #5"
    echo "  $0 --go-tag pr-5 --rust-tag pr-5      # Deploy both from PR #5"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --hetzner)
            USE_HETZNER=true
            shift
            ;;
        --go-tag)
            GO_TAG="$2"
            shift 2
            ;;
        --rust-tag)
            RUST_TAG="$2"
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
echo "  Go vs Rust Benchmark Setup"
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

    if kind get clusters 2>/dev/null | grep -q "redis-benchmark"; then
        print_warning "Deleting existing redis-benchmark cluster..."
        kind delete cluster --name redis-benchmark
    fi

    if kind get clusters 2>/dev/null | grep -q "go-vs-rust"; then
        print_warning "Deleting existing go-vs-rust cluster..."
        kind delete cluster --name go-vs-rust
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
echo "Step 5: Deploying Go and Rust servers..."
echo "-----------------------------------------"

kubectl create namespace go-server-vs-rust-server --dry-run=client -o yaml | kubectl apply -f -

print_status "Deploying applications (go-server:${GO_TAG}, rust-server:${RUST_TAG})..."
sed \
  -e "s|ghcr.io/huseyinbabal/benchmarks/go-server:latest|ghcr.io/huseyinbabal/benchmarks/go-server:${GO_TAG}|g" \
  -e "s|ghcr.io/huseyinbabal/benchmarks/rust-server:latest|ghcr.io/huseyinbabal/benchmarks/rust-server:${RUST_TAG}|g" \
  k8s/deployments.yaml | kubectl apply -f -

print_status "Waiting for deployments to be ready..."
kubectl wait --for=condition=available deployment/hash-go -n go-server-vs-rust-server --timeout=120s
kubectl wait --for=condition=available deployment/hash-rust -n go-server-vs-rust-server --timeout=120s

print_status "Applications deployed"
kubectl get pods -n go-server-vs-rust-server -o wide

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

kubectl create configmap k6-test-hash-go \
  --from-file=test.js=k6/test-go.js \
  -n go-server-vs-rust-server \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap k6-test-hash-rust \
  --from-file=test.js=k6/test-rust.js \
  -n go-server-vs-rust-server \
  --dry-run=client -o yaml | kubectl apply -f -

print_status "k6 test ConfigMaps created"

# Summary
echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "Deployed images:"
echo "  go-server:   ghcr.io/huseyinbabal/benchmarks/go-server:${GO_TAG}"
echo "  rust-server: ghcr.io/huseyinbabal/benchmarks/rust-server:${RUST_TAG}"
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
echo ""
echo "3. Watch the tests:"
echo "   kubectl get testruns -n go-server-vs-rust-server -w"
echo ""
echo "4. View pod status:"
echo "   kubectl get pods -n go-server-vs-rust-server -w"
echo ""
echo "5. In Grafana, select your run from the 'Run' dropdown to view the benchmark"
echo ""
print_status "Happy benchmarking!"
