# Installing Temporal on Kubernetes

This guide covers installing the Temporal server Helm chart and registering the
Datafold logical namespace. Complete [PostgreSQL setup](prerequisites.md#postgresql)
before starting here.

> **Support scope:** Temporal is a third-party open-source component. Datafold
> provides these instructions as guidance, but support is scoped to the Datafold
> application. For Temporal server issues, refer to the
> [Temporal documentation](https://docs.temporal.io/).

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Kubernetes Namespace: temporal                         │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │  Temporal    │  │  Temporal    │  │  Temporal    │   │
│  │  Frontend    │  │  History     │  │  Matching    │   │
│  │  :7233       │  │  :7234       │  │  :7235       │   │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘   │
│         │                 │                 │           │
│  ┌──────┴────────┐  ┌────┴─────────┐                    │
│  │  Temporal     │  │  Temporal    │                    │
│  │  Worker :7239 │  │  Web UI      │                    │
│  └───────────────┘  │  :8080       │                    │
│                     └──────────────┘                    │
│  ┌───────────────┐                                      │
│  │  Admin Tools  │                                      │
│  └───────────────┘                                      │
└──────────────────────────┬──────────────────────────────┘
                           │ :5432
                           │
┌──────────────────────────┴──────────────────────────────┐
│  PostgreSQL (managed or Zalando in-cluster)             │
│  DBs: temporal, temporal_visibility                     │
└─────────────────────────────────────────────────────────┘
```

Temporal consists of four server services (Frontend, History, Matching, Worker),
a Web UI, and admin tools — all running in the `temporal` Kubernetes namespace.
All state is stored in PostgreSQL.

---

## Step 1: Add the Helm Repository

```bash
helm repo add temporal https://go.temporal.io/helm-charts
helm repo update
```

**Pin the chart to version `0.73.2`.** This guide's values format (legacy
`server.config.persistence.default`/`visibility` stores, top-level
`postgresql`/`cassandra`/`mysql`/`prometheus`/`grafana`/`elasticsearch`
toggles) matches that release. Chart versions `1.1.0` and later restructured
persistence under `server.config.persistence.datastores` and removed those
top-level keys outright — applying this guide's values to a newer chart fails
at render time. Confirm it's available:

```bash
helm search repo temporal/temporal --versions | grep 0.73.2
```

Do not substitute a newer `CHART VERSION` without first reworking the values
below for the new schema.

---

## Step 2: Create the Temporal Values File

Create `temporal-values.yaml`. Replace `<RDS_ENDPOINT>` with the hostname of
your managed PostgreSQL instance (or use the
[Zalando values file](postgres-zalando.md#temporal-values-file-zalando-path) if
running in-cluster).

```yaml
server:
  config:
    persistence:
      default:
        driver: "sql"
        sql:
          driver: "postgres12"
          host: <RDS_ENDPOINT>
          port: 5432
          database: temporal
          user: temporal
          existingSecret: temporal-db-credentials
          maxConns: 20
          maxIdleConns: 20
          maxConnLifetime: "1h"
          tls:
            enabled: true
            enableHostVerification: false

      visibility:
        driver: "sql"
        sql:
          driver: "postgres12"
          host: <RDS_ENDPOINT>
          port: 5432
          database: temporal_visibility
          user: temporal
          existingSecret: temporal-db-credentials
          maxConns: 20
          maxIdleConns: 20
          maxConnLifetime: "1h"
          tls:
            enabled: true
            enableHostVerification: false

  frontend:
    resources:
      requests: { cpu: "250m", memory: "256Mi" }
      limits:   { cpu: "500m", memory: "512Mi" }

  history:
    resources:
      requests: { cpu: "500m", memory: "512Mi" }
      limits:   { cpu: "1",    memory: "1Gi"   }

  matching:
    resources:
      requests: { cpu: "250m", memory: "256Mi" }
      limits:   { cpu: "500m", memory: "512Mi" }

  worker:
    resources:
      requests: { cpu: "250m", memory: "256Mi" }
      limits:   { cpu: "500m", memory: "512Mi" }

cassandra:
  enabled: false

mysql:
  enabled: false

postgresql:
  enabled: false

prometheus:
  enabled: false

grafana:
  enabled: false

elasticsearch:
  enabled: false

schema:
  createDatabase:
    enabled: false
  setup:
    enabled: true
  update:
    enabled: true
```

---

## Optional: Datadog Metrics Collection

If the cluster runs the Datadog Agent with Autodiscovery, add these values to
`temporal-values.yaml` to scrape Temporal's OpenMetrics endpoint. **Skip this
section if you don't use Datadog for monitoring** — Temporal runs identically
either way, and none of this is required for the install steps above.

First, switch the internal metrics reporter to the OpenTelemetry framework.
This is what makes Temporal's histogram metrics (latencies) exportable in a
form the Datadog OpenMetrics check can consume:

```yaml
server:
  config:
    metrics:
      prometheus:
        framework: opentelemetry
        handlerPath: /metrics
        listenAddress: 0.0.0.0:9090
        timerType: histogram
```

Then annotate each service so the Agent picks up its metrics endpoint. The
`metrics` allow-list is scoped per component — each service only emits a
subset (for example, only Matching emits backlog/lag metrics, and only
Frontend and History track workflow outcome counters):

```yaml
server:
  frontend:
    podAnnotations:
      ad.datadoghq.com/temporal-frontend.checks: |
        {
          "openmetrics": {
            "instances": [{
              "openmetrics_endpoint": "http://%%host%%:9090/metrics",
              "namespace": "temporal_server",
              "metrics": ["service_requests", "service_latency", "service_error_with_type",
                          "persistence_latency", "workflow_success",
                          "workflow_failed", "workflow_timeout", "workflow_cancel",
                          "no_poller_tasks", "poll_success", "poll_timeouts",
                          "task_requests"],
              "collect_histogram_buckets": true,
              "histogram_buckets_as_distributions": true
            }]
          }
        }

  history:
    podAnnotations:
      ad.datadoghq.com/temporal-history.checks: |
        {
          "openmetrics": {
            "instances": [{
              "openmetrics_endpoint": "http://%%host%%:9090/metrics",
              "namespace": "temporal_server",
              "metrics": ["service_requests", "service_latency", "service_error_with_type",
                          "persistence_latency", "workflow_success",
                          "workflow_failed", "workflow_timeout", "workflow_cancel",
                          "task_requests"],
              "collect_histogram_buckets": true,
              "histogram_buckets_as_distributions": true
            }]
          }
        }

  matching:
    podAnnotations:
      ad.datadoghq.com/temporal-matching.checks: |
        {
          "openmetrics": {
            "instances": [{
              "openmetrics_endpoint": "http://%%host%%:9090/metrics",
              "namespace": "temporal_server",
              "metrics": ["service_requests", "service_latency", "service_error_with_type",
                          "approximate_backlog_count", "approximate_backlog_age_seconds", "task_lag_per_tl",
                          "no_poller_tasks", "poll_success", "poll_timeouts"],
              "collect_histogram_buckets": true,
              "histogram_buckets_as_distributions": true
            }]
          }
        }

  worker:
    podAnnotations:
      ad.datadoghq.com/temporal-worker.checks: |
        {
          "openmetrics": {
            "instances": [{
              "openmetrics_endpoint": "http://%%host%%:9090/metrics",
              "namespace": "temporal_server",
              "metrics": ["service_requests", "service_latency", "service_error_with_type",
                          "persistence_latency"],
              "collect_histogram_buckets": true,
              "histogram_buckets_as_distributions": true
            }]
          }
        }
```

`%%host%%` is a Datadog Autodiscovery template variable resolved to the pod IP
at scrape time — leave it as written. Merge these values into
`temporal-values.yaml` before running the `helm upgrade --install` in Step 3
below (or layer them in as a second `--values` file).

---

## Step 3: Install Temporal

```bash
helm upgrade --install temporal temporal/temporal \
  --namespace temporal --create-namespace \
  --values temporal-values.yaml \
  --version 0.73.2 \
  --timeout 5m
```

### Verify Pods

Wait for all services to become ready:

```bash
kubectl get pods -n temporal -l app.kubernetes.io/instance=temporal
```

All pods should reach `Running` / `1/1` status. Schema init jobs will show as
`Completed`.

### Resource Sizing

The limits above are sized for a single-replica deployment, which is sufficient
for the Datafold workload.

| Component | Role | CPU request | CPU limit | Memory request | Memory limit |
|-----------|------|-------------|-----------|----------------|--------------|
| Frontend | gRPC API gateway | 250m | 500m | 256Mi | 512Mi |
| History | Workflow state, timers, queues | 500m | 1 | 512Mi | 1Gi |
| Matching | Task routing to workers | 250m | 500m | 256Mi | 512Mi |
| Worker (system) | Internal housekeeping | 250m | 500m | 256Mi | 512Mi |

---

## Step 4: Register the Datafold Namespace

Each Datafold deployment uses its own Temporal logical namespace, named
`<DEPLOYMENT_NAME>-datafold` by convention. This is a one-time operation
performed after the Temporal Helm chart is running.

```bash
kubectl exec -it deploy/temporal-admintools -n temporal -- \
  temporal operator namespace create \
    --address temporal-frontend:7233 \
    --namespace <DEPLOYMENT_NAME>-datafold \
    --retention 360h
```

The `--retention` flag controls how long completed workflow history is kept.
360 hours (15 days) balances storage cost against the ability to inspect
completed workflow runs.

To update the retention on an **existing** namespace (e.g. after changing this
setting post-install), use `update` instead of `create`:

```bash
kubectl exec -it deploy/temporal-admintools -n temporal -- \
  temporal operator namespace update \
    --address temporal-frontend:7233 \
    --namespace <DEPLOYMENT_NAME>-datafold \
    --retention 360h
```

After creation, the namespace persists in Temporal's PostgreSQL database.
Datafold workers connect to this namespace — they do not create it themselves.

---

## Verification

### Check Pods

```bash
kubectl get pods -n temporal
```

All Temporal services (frontend, history, matching, worker) should be `Running`.
Schema init jobs should show `Completed`.

### Access the Web UI

```bash
kubectl port-forward svc/temporal-web -n temporal 8080:8080
```

Open `http://localhost:8080`, switch to the `<DEPLOYMENT_NAME>-datafold`
namespace, and confirm it is listed and accessible.

---

## Next Step

Install [KEDA](keda.md) before deploying the Datafold application.

---

## Placeholder Reference

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `<DEPLOYMENT_NAME>` | Your deployment name | `acme`, `production` |
| `<DEPLOYMENT_NAME>-datafold` | Temporal logical namespace | `acme-datafold` |
| `<RDS_ENDPOINT>` | Managed PostgreSQL hostname | `acme-temporal.abc123.us-east-1.rds.amazonaws.com` |
