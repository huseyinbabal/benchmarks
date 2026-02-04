# Rust vs Go HTTP Server Benchmark

A comprehensive benchmark comparing the performance of **Rust** and **Go** HTTP servers under high load conditions on Kubernetes.

Both servers perform an identical workload: computing 100 iterations of SHA256 hashing per request, allowing for a fair comparison of language runtime performance.

## Overview

| Component | Go Server | Rust Server |
|-----------|-----------|-------------|
| Framework | `net/http` (stdlib) | `hyper` + `tokio` |
| Hashing | `crypto/sha256` | `sha2` crate |
| JSON | `encoding/json` | `serde_json` |
| Base Image | `alpine:3.19` | `alpine:3.19` |

### Benchmark Parameters

- **Virtual Users**: Ramps up to 15,000 concurrent users
- **Duration**: 2min ramp-up + 15min sustained load + 30s ramp-down
- **Load Testing Tool**: k6 with k6-operator
- **Metrics**: Prometheus + Grafana

## Prerequisites

- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) (for local testing)
- [hetzner-k3s](https://github.com/vitobotta/hetzner-k3s) (for Hetzner cloud testing)

## Quick Start

### Option 1: Local Kind Cluster (Recommended for Development)

Run the setup script without any arguments to create a local Kind cluster:

```bash
./setup.sh
```

This will:
1. Create a Kind cluster named `go-vs-rust` with multiple node pools
2. Install the Prometheus + Grafana monitoring stack
3. Install the k6-operator for load testing
4. Deploy both Go and Rust servers
5. Configure the Grafana dashboard

### Option 2: Hetzner Cloud (Recommended for Production Benchmarks)

For more realistic benchmarks with dedicated cloud resources, you can provision a k3s cluster on Hetzner Cloud.

#### Step 1: Set up Hetzner Cloud

1. Create a [Hetzner Cloud](https://www.hetzner.com/cloud) account
2. Generate an API token from the Hetzner Cloud Console
3. Export your token:
   ```bash
   export HCLOUD_TOKEN=your_token_here
   ```

#### Step 2: Create the Cluster

Use [hetzner-k3s](https://github.com/vitobotta/hetzner-k3s) to provision the cluster:

```bash
hetzner-k3s create --config iac/hetzner-k3s-cluster.yaml
```

**Cluster Specification:**

| Node Pool | Instance Type | vCPUs | RAM | Count | Purpose |
|-----------|---------------|-------|-----|-------|---------|
| Master | cpx22 | 4 | 8GB | 1 | Control plane |
| app-pool | cpx32 | 8 | 16GB | 2 | Go & Rust servers |
| monitoring-pool | cpx32 | 8 | 16GB | 1 | Prometheus, Grafana |
| client-pool | cpx42 | 16 | 32GB | 2 | k6 load generators |

#### Step 3: Configure kubectl

```bash
export KUBECONFIG=./kubeconfig
```

#### Step 4: Run the Setup Script with Hetzner Flag

```bash
./setup.sh --hetzner
```

This skips Kind cluster creation and deploys all components to your Hetzner k3s cluster.

#### Cleanup Hetzner Resources

```bash
hetzner-k3s delete --config iac/hetzner-k3s-cluster.yaml
```

## Running the Benchmarks

### 1. Access Grafana

```bash
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
```

Open [http://localhost:3000](http://localhost:3000) and log in:
- **Username**: `admin`
- **Password**: `prom-operator`

Navigate to the **"Go vs Rust Benchmark"** dashboard.

### 2. Start the Load Tests

```bash
kubectl apply -f k6/testruns.yaml
```

### 3. Monitor Progress

Watch the test runs:
```bash
kubectl get testruns -n go-server-vs-rust-server -w
```

Watch the pods:
```bash
kubectl get pods -n go-server-vs-rust-server -w
```

## Project Structure

```
.
├── setup.sh                     # Main setup script
├── kind-config.yaml             # Kind cluster configuration
├── monitoring-values.yaml       # Prometheus/Grafana Helm values
├── k6-values.yaml               # k6-operator Helm values
├── go-server/
│   ├── main.go                  # Go HTTP server
│   └── Dockerfile
├── rust-server/
│   ├── src/main.rs              # Rust HTTP server
│   ├── Cargo.toml
│   └── Dockerfile
├── k8s/
│   ├── deployments.yaml         # K8s Deployments & Services
│   └── dashboard-configmap.yaml # Grafana dashboard
├── k6/
│   ├── test-go.js               # k6 test for Go server
│   ├── test-rust.js             # k6 test for Rust server
│   └── testruns.yaml            # k6 TestRun CRDs
└── iac/
    └── hetzner-k3s-cluster.yaml # Hetzner k3s cluster config
```

## API Endpoints

Both servers expose identical endpoints:

| Endpoint | Description |
|----------|-------------|
| `GET /hash` | Performs 100 SHA256 iterations and returns JSON |
| `GET /health` | Health check endpoint |

**Response format:**
```json
{
  "hash": "a1b2c3...",
  "timestamp": "2024-01-01T12:00:00Z",
  "source": "go"  // or "rust"
}
```

## Resource Allocation

Both servers are deployed with identical resource constraints for fair comparison:

| Resource | Request | Limit |
|----------|---------|-------|
| CPU | 100m | 2 cores |
| Memory | 64Mi | 3Gi |

## Grafana Dashboard Metrics

The pre-configured dashboard displays:

- **Requests per Second** - Throughput comparison
- **p95 / p99 Latency** - Tail latency comparison
- **Virtual Users** - Active load over time
- **Average Iteration Latency** - Mean response time
- **Total Requests** - Request counts per server
- **Failed Requests** - Error tracking
- **CPU Usage** - Per-server CPU consumption
- **Memory Usage** - Per-server memory (RSS)

## Customization

### Modify Load Test Parameters

Edit `k6/test-go.js` and `k6/test-rust.js`:

```javascript
export const options = {
  stages: [
    { duration: "2m", target: 15000 },   // Ramp up
    { duration: "15m", target: 15000 },  // Sustained load
    { duration: "30s", target: 0 },      // Ramp down
  ],
  // ...
};
```

### Adjust Server Resources

Edit `k8s/deployments.yaml` to modify CPU/memory limits:

```yaml
resources:
  limits:
    cpu: "2"
    memory: "3Gi"
  requests:
    cpu: "100m"
    memory: "64Mi"
```

## Troubleshooting

### Pods stuck in Pending state

Check node pool labels:
```bash
kubectl get nodes --show-labels | grep pool
```

### k6 tests not starting

Verify k6-operator is running:
```bash
kubectl get pods -n k6-operator
```

### No metrics in Grafana

Check Prometheus targets:
```bash
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
```
Then visit [http://localhost:9090/targets](http://localhost:9090/targets)

## License

MIT
