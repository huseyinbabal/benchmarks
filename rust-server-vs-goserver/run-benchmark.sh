#!/bin/bash

# Run Benchmark Script
# Launches k6 test runs with a unique run ID for filtering in Grafana

set -e

RUN_ID=""

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --run-id ID    Unique identifier for this benchmark run (default: auto-generated timestamp)"
    echo "                 Used to filter runs in Grafana dashboard"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Run with auto-generated ID (run-20260206-143000)"
    echo "  $0 --run-id iteration-1      # Tag this run as 'iteration-1'"
    echo "  $0 --run-id pr-5-test        # Tag this run as 'pr-5-test'"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --run-id)
            RUN_ID="$2"
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

# Generate run ID if not provided
if [ -z "$RUN_ID" ]; then
    RUN_ID="run-$(date +%Y%m%d-%H%M%S)"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

echo "=========================================="
echo "  Running Benchmark: ${RUN_ID}"
echo "=========================================="
echo ""

# Clean up previous test runs
print_warning "Cleaning up previous test runs..."
kubectl delete testruns -n go-server-vs-rust-server --all 2>/dev/null || true

# Wait for old pods to terminate
echo "Waiting for old k6 pods to terminate..."
kubectl wait --for=delete pod -l app=k6 -n go-server-vs-rust-server --timeout=60s 2>/dev/null || true
sleep 2

# Apply new test runs with the run ID
print_status "Applying test runs with run ID '${RUN_ID}'..."
sed \
  -e "s|run=latest|run=${RUN_ID}|g" \
  -e "s|value: \"latest\"|value: \"${RUN_ID}\"|g" \
  k6/testruns.yaml | kubectl apply -f -

print_status "Test runs started"
echo ""
echo "Run ID: ${RUN_ID}"
echo ""
echo "Monitor progress:"
echo "  kubectl get testruns -n go-server-vs-rust-server -w"
echo "  kubectl get pods -n go-server-vs-rust-server -w"
echo ""
echo "In Grafana, select '${RUN_ID}' from the 'Run' dropdown to view results"
