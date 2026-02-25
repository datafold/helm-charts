# Temporal and PostgreSQL Prerequisites

Datafold uses [Temporal](https://temporal.io/) for workflow orchestration.
Temporal requires a PostgreSQL database for persistence. Both must be deployed
and healthy **before** deploying the Datafold application.

This guide walks you through deploying PostgreSQL (via the Zalando Postgres
Operator) and Temporal on Kubernetes. It is cloud-agnostic and works on
AWS (EKS), GCP (GKE), and Azure (AKS).

> **Support scope:** Temporal, PostgreSQL, and the Zalando Postgres Operator
> are third-party open-source components. Datafold provides these deployment
> instructions as guidance to help you get started, but **Datafold's support
> is scoped to the Datafold application** that runs on top of these
> dependencies. You are responsible for the ongoing operation, maintenance,
> upgrades, and troubleshooting of Temporal and PostgreSQL in your
> environment. For issues with these components, refer to their respective
> upstream documentation:
>
> - [Temporal documentation](https://docs.temporal.io/)
> - [Zalando Postgres Operator documentation](https://postgres-operator.readthedocs.io/)
> - [PostgreSQL documentation](https://www.postgresql.org/docs/)

---

## Architecture Overview

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
                           │ temporal-database.postgres-operator
                           │ .svc.cluster.local:5432
┌──────────────────────────┴──────────────────────────────┐
│  Kubernetes Namespace: postgres-operator                │
│                                                         │
│  ┌──────────────────────────────┐                       │
│  │  PostgreSQL                  │                       │
│  │  (Zalando Operator)          │  ┌──────────────────┐ │
│  │  temporal-database :5432     │  │  Backup Storage  │ │
│  │  DBs: temporal,              │──│  (S3/GCS/Azure)  │ │
│  │       temporal_visibility    │  └──────────────────┘ │
│  └──────────────────────────────┘                       │
└─────────────────────────────────────────────────────────┘
```

Temporal consists of four server services (Frontend, History, Matching, Worker),
a Web UI, and admin tools. These run in the `temporal` Kubernetes namespace.
All state is stored in PostgreSQL, which runs in the `postgres-operator`
namespace managed by the Zalando Postgres Operator. Logical backups go to
cloud object storage.

---

## Deployment Order

Deploy components in this order. Each step depends on the previous one.

| Step | Component | Notes |
|------|-----------|-------|
| 1 | Cloud storage bucket | S3 / GCS / Azure Blob for PostgreSQL backups |
| 2 | IAM / Workload Identity | Service account binding so pods can write to the bucket |
| 3 | Zalando Postgres Operator | Helm chart `postgres-operator` v1.14.0+ |
| 4 | PostgreSQL cluster CR | Creates `temporal-database` with two databases |
| 5 | Temporal Helm chart | Points at the PostgreSQL cluster |
| 6 | Grant DML privileges | One-time SQL grants for the runtime database user |
| 7 | Temporal namespace | One-time admin operation via `temporal-admintools` pod |

---

## Step 1: Create Backup Storage

Create an object storage bucket for PostgreSQL logical backups. Enable
server-side encryption and set a lifecycle policy to expire old backups
(7 days recommended).

| Cloud | Service | Example Bucket Name |
|-------|---------|---------------------|
| AWS | S3 | `<DEPLOYMENT_NAME>-postgres-backups` |
| GCP | Cloud Storage | `<DEPLOYMENT_NAME>-postgres-backups` |
| Azure | Blob Storage | Container in a Storage Account |

---

## Step 2: Create IAM / Workload Identity Binding

Grant the `postgres-pod` Kubernetes service account permission to read and
write to the backup bucket.

### AWS (EKS)

Create an IAM role with an OIDC trust policy for the EKS cluster. The role
must grant the following S3 actions, restricted to the backup bucket ARN:

- Bucket-level (`arn:aws:s3:::<BUCKET>`): `s3:ListBucket`, `s3:GetBucketLocation`
- Object-level (`arn:aws:s3:::<BUCKET>/*`): `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`

### GCP (GKE)

Create a Google Service Account (GSA) with `roles/storage.objectAdmin`.
**Scope the role binding to the backup bucket only** -- bind at the bucket
level, not at the project level. Then bind the GSA to the Kubernetes service
account via Workload Identity Federation:

```bash
gcloud iam service-accounts add-iam-policy-binding \
  <GSA_NAME>@<PROJECT_ID>.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:<PROJECT_ID>.svc.id.goog[postgres-operator/postgres-pod]"
```

### Azure (AKS)

Create a Managed Identity with `Storage Blob Data Contributor`. **Scope the
role assignment to the backup storage container only** -- assign at the
container scope, not at the subscription or resource group level. Create a
federated credential for the AKS cluster:

```bash
az identity federated-credential create \
  --name postgres-pod-fedcred \
  --identity-name <MANAGED_IDENTITY_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --issuer <AKS_OIDC_ISSUER_URL> \
  --subject system:serviceaccount:postgres-operator:postgres-pod
```

---

## Step 3: Install Zalando Postgres Operator

The Zalando Postgres Operator manages PostgreSQL clusters as Kubernetes custom
resources. It is cluster-scoped and watches all namespaces.

### Add the Helm Repository

```bash
helm repo add postgres-operator-charts \
  https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo update
```

### Create Operator Values File

Create a file called `postgres-operator-values.yaml` with the configuration
for your cloud provider.

#### AWS (EKS)

```yaml
configLogicalBackup:
  logical_backup_provider: "s3"
  logical_backup_s3_bucket: "<DEPLOYMENT_NAME>-postgres-backups"
  logical_backup_s3_region: "<AWS_REGION>"
  logical_backup_s3_sse: "AES256"
  logical_backup_schedule: "30 00 * * *"

configKubernetes:
  pod_service_account_name: "postgres-pod"
  pod_service_account_definition: |
    {
      "apiVersion": "v1",
      "kind": "ServiceAccount",
      "metadata": {
        "name": "postgres-pod",
        "annotations": {
          "eks.amazonaws.com/role-arn": "arn:aws:iam::<ACCOUNT_ID>:role/<DEPLOYMENT_NAME>-postgres-backup"
        }
      }
    }
```

#### GCP (GKE)

```yaml
configLogicalBackup:
  logical_backup_provider: "gcs"
  logical_backup_gcs_bucket: "<DEPLOYMENT_NAME>-postgres-backups"
  logical_backup_schedule: "30 00 * * *"

configKubernetes:
  pod_service_account_name: "postgres-pod"
  pod_service_account_definition: |
    {
      "apiVersion": "v1",
      "kind": "ServiceAccount",
      "metadata": {
        "name": "postgres-pod",
        "annotations": {
          "iam.gke.io/gcp-service-account": "<GSA_NAME>@<PROJECT_ID>.iam.gserviceaccount.com"
        }
      }
    }
```

#### Azure (AKS)

```yaml
configLogicalBackup:
  logical_backup_provider: "az"
  logical_backup_azure_storage_account_name: "<STORAGE_ACCOUNT>"
  logical_backup_azure_storage_container: "<CONTAINER_NAME>"
  logical_backup_azure_storage_account_key: "<STORAGE_KEY>"
  logical_backup_schedule: "30 00 * * *"

configKubernetes:
  pod_service_account_name: "postgres-pod"
  pod_service_account_definition: |
    {
      "apiVersion": "v1",
      "kind": "ServiceAccount",
      "metadata": {
        "name": "postgres-pod",
        "labels": {
          "azure.workload.identity/use": "true"
        },
        "annotations": {
          "azure.workload.identity/client-id": "<MANAGED_IDENTITY_CLIENT_ID>"
        }
      }
    }
```

### Install the Operator

```bash
helm upgrade --install postgres-operator postgres-operator-charts/postgres-operator \
  --namespace postgres-operator --create-namespace \
  --values postgres-operator-values.yaml \
  --version 1.14.0 \
  --wait --timeout 3m
```

---

## Step 4: Deploy PostgreSQL Cluster

Create a file called `temporal-database.yaml` with the following PostgreSQL
cluster custom resource. The Zalando operator will create a StatefulSet, a
Service named `temporal-database`, and Kubernetes Secrets containing the
database credentials.

```yaml
apiVersion: "acid.zalan.do/v1"
kind: postgresql
metadata:
  name: temporal-database
  namespace: postgres-operator
spec:
  enableLogicalBackup: true
  teamId: "datafold"

  volume:
    size: 20Gi
    storageClass: <STORAGE_CLASS>

  numberOfInstances: 1

  postgresql:
    version: "17"

  users:
    temporal_datafold:
      - superuser
      - createdb
    tuser: []

  databases:
    temporal: temporal_datafold
    temporal_visibility: temporal_datafold

  resources:
    requests:
      cpu: "2"
      memory: "4Gi"
    limits:
      cpu: "2"
      memory: "4Gi"
```

Replace `<STORAGE_CLASS>` with the appropriate StorageClass for your cloud
provider (e.g., `gp3` for AWS, `pd-ssd` for GCP, `managed-premium` for Azure).

### Apply and Wait

```bash
kubectl apply -f temporal-database.yaml
kubectl wait --for=condition=Ready pod/temporal-database-0 \
  -n postgres-operator --timeout=5m
```

### Credentials

The operator creates a Kubernetes Secret for each database user. The two
relevant secrets are:

| User | Secret Name | Purpose |
|------|-------------|---------|
| `temporal_datafold` | `temporal-datafold.temporal-database.credentials.postgresql.acid.zalan.do` | Superuser for schema creation and migrations. Used by Temporal's schema init jobs. |
| `tuser` | `tuser.temporal-database.credentials.postgresql.acid.zalan.do` | Unprivileged runtime user for day-to-day DML operations. Used by the Temporal server. |

**Volume sizing:** 20Gi is adequate for the expected workload. Temporal's
database usage scales with the number of open (in-flight) workflows and
retained history, not the total number of completed workflows.

---

## Step 5: Install Temporal

### Add the Helm Repository

```bash
helm repo add temporal https://go.temporal.io/helm-charts
helm repo update
```

Pin the chart version explicitly in your install command (`--version`) to
ensure reproducible deployments. Use the latest stable version >= 1.0.0. You
can list available versions with:

```bash
helm search repo temporal/temporal --versions
```

### Create Temporal Values File

Create a file called `temporal-values.yaml`. The database password is not
stored in this file -- it is read from the Kubernetes Secret that the Zalando
Postgres Operator creates automatically.

```yaml
server:
  config:
    persistence:
      default:
        driver: "sql"
        sql:
          driver: "postgres12"
          host: temporal-database.postgres-operator.svc.cluster.local
          port: 5432
          database: temporal
          user: tuser
          existingSecret: tuser.temporal-database.credentials.postgresql.acid.zalan.do
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
          host: temporal-database.postgres-operator.svc.cluster.local
          port: 5432
          database: temporal_visibility
          user: tuser
          existingSecret: tuser.temporal-database.credentials.postgresql.acid.zalan.do
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
  enabled: true

prometheus:
  enabled: false

grafana:
  enabled: false

elasticsearch:
  enabled: false

schema:
  createDatabase:
    enabled: true
  setup:
    enabled: true
  update:
    enabled: true
```

### Install Temporal

```bash
helm upgrade --install temporal temporal/temporal \
  --namespace temporal --create-namespace \
  --values temporal-values.yaml \
  --version <CHART_VERSION> \
  --timeout 5m
```

### Verify Pods

Wait for all services to start:

```bash
kubectl get pods -n temporal -l app.kubernetes.io/instance=temporal
```

All pods should reach `Running` / `1/1` status. The schema init jobs will
show as `Completed`.

### Resource Sizing

The resource limits in the values file above are sized for a single-replica
deployment, which is sufficient for the expected Datafold workload.

| Component | Role | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|------|-------------|-----------|----------------|--------------|
| Frontend | gRPC API gateway | 250m | 500m | 256Mi | 512Mi |
| History | Workflow state, timers, queues | 500m | 1 | 512Mi | 1Gi |
| Matching | Task routing to workers | 250m | 500m | 256Mi | 512Mi |
| Worker (system) | Internal housekeeping | 250m | 500m | 256Mi | 512Mi |
| PostgreSQL | Persistence | 2 | 2 | 4Gi | 4Gi |

---

## Step 6: Grant DML Privileges to Runtime User

The Zalando operator creates `tuser` but does not automatically grant it
access to the `temporal` and `temporal_visibility` databases. This must be
done **once** after the Temporal schema init jobs have completed (they create
the tables as `temporal_datafold`).

Connect to the database:

```bash
kubectl exec -it temporal-database-0 -n postgres-operator -- \
  psql -U postgres
```

Run the following SQL:

```sql
GRANT CONNECT ON DATABASE temporal TO tuser;
GRANT CONNECT ON DATABASE temporal_visibility TO tuser;

\c temporal
GRANT USAGE ON SCHEMA public TO tuser;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO tuser;
ALTER DEFAULT PRIVILEGES FOR ROLE temporal_datafold IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO tuser;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO tuser;
ALTER DEFAULT PRIVILEGES FOR ROLE temporal_datafold IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO tuser;

\c temporal_visibility
GRANT USAGE ON SCHEMA public TO tuser;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO tuser;
ALTER DEFAULT PRIVILEGES FOR ROLE temporal_datafold IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO tuser;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO tuser;
ALTER DEFAULT PRIVILEGES FOR ROLE temporal_datafold IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO tuser;
```

The `ALTER DEFAULT PRIVILEGES` statements ensure that tables created by future
schema migrations (run as `temporal_datafold`) are automatically accessible to
`tuser`. This is a one-time operation.

---

## Step 7: Register Temporal Namespace

Each Datafold deployment uses its own Temporal logical namespace, named
`<DEPLOYMENT_NAME>-datafold` by convention. This is a one-time operation
performed after the Temporal Helm chart is deployed.

```bash
kubectl exec -it deploy/temporal-admintools -n temporal -- \
  temporal operator namespace create \
    --namespace <DEPLOYMENT_NAME>-datafold \
    --retention 72h
```

The `--retention` flag controls how long completed workflow history is kept.
72 hours is a reasonable default for debugging.

After creation, the namespace persists in Temporal's PostgreSQL database.
Datafold application workers connect to this namespace -- they do not create
it themselves.

---

## Verification

### Check Temporal Pods

```bash
kubectl get pods -n temporal
```

All Temporal services (frontend, history, matching, worker) should be
`Running`. Schema init jobs should show `Completed`.

### Check PostgreSQL

```bash
kubectl get pods -n postgres-operator -l cluster-name=temporal-database
```

The `temporal-database-0` pod should be `Running` / `1/1`.

### Access the Web UI

The Temporal Web UI is included in the Helm chart and enabled by default.
Access it via port-forward:

```bash
kubectl port-forward svc/temporal-web -n temporal 8080:8080
```

Open `http://localhost:8080`, switch to the `<DEPLOYMENT_NAME>-datafold`
namespace, and confirm it is listed and accessible.

---

## Placeholder Reference

| Placeholder | Description | Examples |
|-------------|-------------|----------|
| `<DEPLOYMENT_NAME>` | Your deployment or environment name | `acme`, `staging`, `production` |
| `<DEPLOYMENT_NAME>-datafold` | Temporal logical namespace (convention) | `acme-datafold`, `staging-datafold` |
| `<STORAGE_CLASS>` | Kubernetes StorageClass for persistent volumes | `gp3`, `pd-ssd`, `managed-premium` |
| `<CHART_VERSION>` | Temporal Helm chart version (>= 1.0.0) | `1.0.0`, `1.1.0` |
| `<ACCOUNT_ID>` | AWS account ID | `524263733165` |
| `<AWS_REGION>` | AWS region | `us-west-2` |
| `<PROJECT_ID>` | GCP project ID | `datafold-production` |
| `<GSA_NAME>` | GCP service account name for backups | `postgres-backup` |
| `<MANAGED_IDENTITY_CLIENT_ID>` | Azure managed identity client ID | (UUID) |
| `<MANAGED_IDENTITY_NAME>` | Azure managed identity name | `postgres-backup-identity` |
| `<RESOURCE_GROUP>` | Azure resource group | `datafold-rg` |
| `<AKS_OIDC_ISSUER_URL>` | AKS cluster OIDC issuer URL | `https://oidc.prod-aks.azure.com/...` |
| `<STORAGE_ACCOUNT>` | Azure storage account name (backups) | `datafoldbackups` |
| `<CONTAINER_NAME>` | Azure blob container name (backups) | `postgres-backups` |
| `<STORAGE_KEY>` | Azure storage account key (backups) | (key string) |
