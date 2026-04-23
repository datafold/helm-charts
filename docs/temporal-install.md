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

Pin the chart version explicitly to ensure reproducible deployments. List
available versions:

```bash
helm search repo temporal/temporal --versions
```

The `APP VERSION` column shows the Temporal server version. Note the `CHART VERSION`
for the app version you want — use that as `<CHART_VERSION>` below.

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

## Step 3: Install Temporal

```bash
helm upgrade --install temporal temporal/temporal \
  --namespace temporal --create-namespace \
  --values temporal-values.yaml \
  --version <CHART_VERSION> \
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
    --retention 72h
```

The `--retention` flag controls how long completed workflow history is kept.
72 hours is a reasonable default for debugging.

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
| `<CHART_VERSION>` | Temporal Helm chart version | `0.73.2`, `1.0.0` |
