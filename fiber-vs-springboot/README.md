# Fiber vs Spring Boot HTTP Server Benchmark

A comprehensive benchmark comparing the performance of **Go Fiber** and **Spring Boot 4** HTTP servers under high load conditions on Kubernetes.

Both servers perform an identical workload: computing 100 iterations of SHA256 hashing per request, allowing for a fair comparison of language runtime performance.

## Overview

| Component | Fiber Server | Spring Boot Server |
|-----------|--------------|-------------------|
| Framework | Go Fiber v3 | Spring Boot 4.0.2 |
| Runtime | Go 1.25 | Java 25 with Virtual Threads |
| Hashing | `crypto/sha256` | `MessageDigest` |
| JSON | `encoding/json` | Jackson |
| Base Image | `alpine:latest` | `eclipse-temurin:25-jre` |
| Metrics | Prometheus (port 2112) | Spring Boot Actuator (port 8080) |

### Benchmark Parameters

- **Virtual Users**: Ramps up to 15,000 concurrent users
- **Duration**: 2min ramp-up + 15min sustained load + 30s ramp-down
- **Load Testing Tool**: k6 with k6-operator
- **Metrics**: Prometheus + Grafana

### Key Metrics Tracked

- **HTTP Performance**: RPS, P50/P90/P95/P99 latency
- **Resource Usage**: CPU, Memory
- **Concurrency**: Goroutines (Fiber) vs Threads (Spring Boot with Virtual Threads)
- **Throughput**: Total successful/failed requests

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
1. Create a Kind cluster named `fiber-vs-springboot` with multiple node pools
2. Install the Prometheus + Grafana monitoring stack
3. Install the k6-operator for load testing
4. Deploy both Fiber and Spring Boot servers
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
| app-pool | cpx42 | 16 | 32GB | 2 | Fiber & Spring Boot servers |
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

Navigate to the **"Fiber vs Spring Boot Benchmark"** dashboard.

**Note:** Use the **"Run"** dropdown at the top of the dashboard to filter results by specific benchmark runs.

### 2. Start the Load Tests

**Option A: Using the run-benchmark.sh script (Recommended)**

This script automatically generates a unique run ID and applies the test runs:

```bash
./run-benchmark.sh --run-id iteration-1
```

Or let it auto-generate a timestamp-based ID:

```bash
./run-benchmark.sh
# Output: Running Benchmark: run-20260209-143052
```

**Option B: Manual run with kubectl**

```bash
kubectl apply -f k6/testruns.yaml
```

Note: Manual runs will use the default "latest" tag, making it harder to distinguish between different benchmark runs.

### 3. Monitor Progress

Watch the test runs:
```bash
kubectl get testruns -n fiber-vs-springboot -w
```

Watch the pods:
```bash
kubectl get pods -n fiber-vs-springboot -w
```

## Project Structure

```
.
├── setup.sh                     # Main setup script
├── run-benchmark.sh             # Run benchmarks with unique run ID
├── kind-config.yaml             # Kind cluster configuration
├── monitoring-values.yaml       # Prometheus/Grafana Helm values
├── k6-values.yaml               # k6-operator Helm values
├── go-fiber/
│   ├── main.go                  # Go Fiber HTTP server
│   ├── go.mod
│   └── Dockerfile
├── java-springboot/
│   ├── src/
│   │   └── main/
│   │       ├── java/...         # Spring Boot application
│   │       └── resources/
│   │           └── application.properties
│   ├── pom.xml
│   └── Dockerfile
├── k8s/
│   ├── deployments.yaml         # K8s Deployments & Services
│   └── dashboard-configmap.yaml # Grafana dashboard
├── k6/
│   ├── test-fiber.js            # k6 test for Fiber server
│   ├── test-springboot.js       # k6 test for Spring Boot server
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

**Fiber Response format:**
```json
{
  "hash": "a1b2c3...",
  "timestamp": 1234567890,
  "source": "go-fiber"
}
```

**Spring Boot Response format:**
```json
{
  "hash": "a1b2c3...",
  "timestamp": "2024-01-01T12:00:00Z",
  "source": "springboot"
}
```

## Metrics Endpoints

### Fiber Server (Go)
- **Application**: `http://fiber-server:3000/hash`
- **Prometheus Metrics**: `http://fiber-server:2112/metrics`
  - `go_goroutines`: Number of active goroutines

### Spring Boot Server (Java)
- **Application**: `http://springboot-server:8080/hash`
- **Prometheus Metrics**: `http://springboot-server:8080/actuator/prometheus`
  - `jvm_threads_live_threads`: Number of live threads
  - `jvm_threads_daemon_threads`: Number of daemon threads
  - `jvm_memory_*`: JVM memory metrics

## Resource Allocation

Both servers are deployed with identical resource constraints for fair comparison:

| Resource | Request | Limit |
|----------|---------|-------|
| CPU | 1 core | 14 cores |
| Memory | 512Mi | 28Gi |

## Grafana Dashboard Metrics

The pre-configured dashboard displays:

- **Requests per Second** - Throughput comparison between Fiber and Spring Boot
- **Goroutines / Threads Count** - Live concurrency tracking
- **P95 / P99 Latency** - Tail latency comparison
- **Memory Usage** - Per-server memory consumption
- **CPU Usage** - Per-server CPU consumption
- **Total Requests (24h)** - Request counts per server

## Run ID Management

Each benchmark run can be tagged with a unique **Run ID** to help distinguish between different test iterations. This is especially useful when:

- Running multiple benchmark iterations with different configurations
- Testing different code versions (e.g., PRs)
- Comparing performance before/after optimizations

### Using Run IDs

The `run-benchmark.sh` script manages run IDs automatically:

```bash
# Auto-generate a timestamp-based run ID
./run-benchmark.sh
# Creates: run-20260209-143052

# Use a custom run ID for easy identification
./run-benchmark.sh --run-id iteration-1
./run-benchmark.sh --run-id pr-123-test
./run-benchmark.sh --run-id baseline-fiber-v3
```

### Viewing Run Results in Grafana

1. Open the Grafana dashboard
2. Look for the **"Run"** dropdown at the top of the dashboard
3. Select a specific run ID to view its results, or select "All" to compare multiple runs
4. The dropdown automatically populates with all available run IDs from your benchmark history

### Run ID Best Practices

- **Descriptive names**: Use meaningful names like `iteration-1`, `pr-42`, `baseline` instead of random strings
- **Consistency**: Use a naming convention (e.g., `iteration-N`, `pr-N-description`)
- **Documentation**: Keep a log of what each run ID represents for future reference

## Customization

### Modify Load Test Parameters

Edit `k6/test-fiber.js` and `k6/test-springboot.js`:

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
    cpu: "14"
    memory: "28Gi"
  requests:
    cpu: "1"
    memory: "512Mi"
```

## Technology Highlights

### Fiber Server (Go)
- Uses Go's native goroutines for concurrency
- Lightweight and efficient memory footprint
- Fixed-size array allocations in hash loop to avoid heap allocations
- Prometheus metrics exported on separate port (2112)

### Spring Boot Server (Java)
- Leverages Java 25 Virtual Threads for massive concurrency
- Spring Boot 4.0.2 with modern reactive capabilities
- Built-in Actuator for comprehensive metrics
- JVM optimizations and garbage collection tuning

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

### Fiber server metrics not appearing

Verify the Prometheus scrape config is correctly targeting port 2112:
```bash
kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus -o yaml | grep -A 10 "job_name: fiber"
```

## License

MIT
