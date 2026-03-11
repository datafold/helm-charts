# Temporal and PostgreSQL Prerequisites

Datafold uses [Temporal](https://temporal.io/) for workflow orchestration.
Temporal requires a PostgreSQL database for persistence. Both must be deployed
and healthy **before** deploying the Datafold application.

This guide walks you through setting up PostgreSQL and Temporal on Kubernetes.
The recommended approach is to use a **managed PostgreSQL service** (AWS RDS,
GCP Cloud SQL, or Azure Database for PostgreSQL) — these are simpler to
operate, handle backups natively, and require no additional Kubernetes
operators. If you prefer to run PostgreSQL inside the cluster, see the
[Alternative: Zalando Postgres Operator](#alternative-zalando-postgres-operator)
section at the end of this guide.

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
                           │ <RDS_ENDPOINT>:5432
                           │
┌──────────────────────────┴──────────────────────────────┐
│  Managed PostgreSQL (AWS RDS / GCP Cloud SQL / Azure)   │
│                                                         │
│  DBs: temporal, temporal_visibility                     │
│  Backups: managed by cloud provider                     │
└─────────────────────────────────────────────────────────┘
```

Temporal consists of four server services (Frontend, History, Matching, Worker),
a Web UI, and admin tools. These run in the `temporal` Kubernetes namespace.
All state is stored in PostgreSQL. With a managed database, backups and
high-availability are handled by the cloud provider.

---

## Deployment Order

Deploy components in this order. Each step depends on the previous one.

| Step | Component | Notes |
|------|-----------|-------|
| 1 | Managed PostgreSQL instance | AWS RDS, GCP Cloud SQL, or Azure Database |
| 2 | Database setup | Two databases, dedicated user, Kubernetes Secret |
| 3 | Create Temporal namespace | Required before deploying Temporal |
| 4 | Temporal Helm chart | Points at the managed PostgreSQL instance |
| 5 | Temporal namespace | One-time admin operation via `temporal-admintools` pod |

---

## Step 1: Provision a Managed PostgreSQL Instance

Create a PostgreSQL 17 instance using your cloud provider's managed
database service. The key requirements are:

- **Network connectivity** – the instance must be reachable from the
  Kubernetes cluster on port 5432. Place the database in the same VPC (or a
  peered VPC) and allow inbound 5432 from the cluster's node security
  group / firewall rules.
- **PostgreSQL version** – 17 required.
- **Instance sizing** – `db.t3.medium` (2 vCPU / 4 GiB) or equivalent is
  adequate for the expected Datafold workload.
- **Storage** – 20 GiB with autoscaling enabled is a reasonable starting
  point.

### AWS RDS

Create a PostgreSQL RDS instance in the same VPC as your EKS cluster:

```bash
aws rds create-db-instance \
  --db-instance-identifier <DEPLOYMENT_NAME>-temporal \
  --db-instance-class db.t3.medium \
  --engine postgres \
  --engine-version "17" \
  --master-username postgres \
  --master-user-password <MASTER_PASSWORD> \
  --allocated-storage 20 \
  --storage-type gp3 \
  --storage-encrypted \
  --vpc-security-group-ids <SECURITY_GROUP_ID> \
  --db-subnet-group-name <SUBNET_GROUP> \
  --no-publicly-accessible \
  --backup-retention-period 7 \
  --region <AWS_REGION>
```

Allow inbound TCP 5432 from the EKS node security group in
`<SECURITY_GROUP_ID>`. Wait for the instance to reach `available` status
before proceeding:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier <DEPLOYMENT_NAME>-temporal \
  --region <AWS_REGION>
```

Retrieve the endpoint:

```bash
aws rds describe-db-instances \
  --db-instance-identifier <DEPLOYMENT_NAME>-temporal \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text \
  --region <AWS_REGION>
```

This is your `<RDS_ENDPOINT>`.

### GCP Cloud SQL

Create a PostgreSQL Cloud SQL instance in the same project and region as
your GKE cluster. Enable the Cloud SQL Admin API first, then use the Cloud
Console or `gcloud`:

```bash
gcloud sql instances create <DEPLOYMENT_NAME>-temporal \
  --database-version=POSTGRES_17 \
  --tier=db-custom-2-4096 \
  --region=<GCP_REGION> \
  --network=<VPC_NETWORK> \
  --no-assign-ip \
  --backup-start-time=02:00 \
  --retained-backups-count=7
```

Use the **Private IP** address of the instance as `<RDS_ENDPOINT>` in
subsequent steps. Ensure your GKE nodes can route to the Cloud SQL private
IP.

### Azure Database for PostgreSQL

Create a Flexible Server instance in the same virtual network as your AKS
cluster:

```bash
az postgres flexible-server create \
  --name <DEPLOYMENT_NAME>-temporal \
  --resource-group <RESOURCE_GROUP> \
  --location <AZURE_REGION> \
  --sku-name Standard_D2s_v3 \
  --tier GeneralPurpose \
  --version 17 \
  --storage-size 32 \
  --vnet <VNET_NAME> \
  --subnet <SUBNET_NAME> \
  --admin-user postgres \
  --admin-password <MASTER_PASSWORD>
```

Use the server's hostname as `<RDS_ENDPOINT>` in subsequent steps.

---

## Step 2: Create Databases, User, and Kubernetes Secret

Once the managed instance is running, connect to it and create the required
databases and user. The `temporal` user needs full DDL privileges so
Temporal's schema init jobs can create tables and indexes on first startup.

```sql
-- Connect as the master/admin user
CREATE USER temporal WITH PASSWORD '<TEMPORAL_DB_PASSWORD>';

CREATE DATABASE temporal OWNER temporal;
CREATE DATABASE temporal_visibility OWNER temporal;

-- Grant all privileges (needed for Temporal's schema init jobs)
GRANT ALL PRIVILEGES ON DATABASE temporal TO temporal;
GRANT ALL PRIVILEGES ON DATABASE temporal_visibility TO temporal;
```

> **Note for AWS RDS:** The master user is not a true superuser. Also grant
> schema-level privileges after connecting to each database:
>
> ```sql
> -- Run while connected to each database
> GRANT ALL ON SCHEMA public TO temporal;
> ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO temporal;
> ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO temporal;
> ```

### Create the Temporal Kubernetes Namespace

```bash
kubectl create namespace temporal
```

### Store Credentials in a Kubernetes Secret

Create a Secret in the `temporal` namespace. The key name must be `password`
(this is what the Temporal Helm chart's `existingSecret` references):

```bash
kubectl create secret generic temporal-db-credentials \
  --namespace temporal \
  --from-literal=password=<TEMPORAL_DB_PASSWORD>
```

---

## Step 3: Create the Temporal Namespace

The `temporal` Kubernetes namespace was already created in Step 2. No
additional action is needed here; this step is listed explicitly so you
can verify before continuing:

```bash
kubectl get namespace temporal
```

---

## Step 4: Install Temporal

### Add the Helm Repository

```bash
helm repo add temporal https://go.temporal.io/helm-charts
helm repo update
```

Pin the chart version explicitly in your install command (`--version`) to
ensure reproducible deployments. List available versions with:

```bash
helm search repo temporal/temporal --versions
```

The `APP VERSION` column shows the Temporal server version. Find the row with
the app version you want and use the corresponding `CHART VERSION` as
`<CHART_VERSION>`.

### Create Temporal Values File

Create a file called `temporal-values.yaml`. Replace `<RDS_ENDPOINT>` with
the hostname of your managed PostgreSQL instance.

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

# Disable the in-cluster PostgreSQL subchart — we use a managed database
postgresql:
  enabled: false

prometheus:
  enabled: false

grafana:
  enabled: false

elasticsearch:
  enabled: false

schema:
  # Databases already exist in the managed instance
  createDatabase:
    enabled: false
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

---

## Step 5: Register Temporal Namespace

Each Datafold deployment uses its own Temporal logical namespace, named
`<DEPLOYMENT_NAME>-datafold` by convention. This is a one-time operation
performed after the Temporal Helm chart is deployed.

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

### Access the Web UI

The Temporal Web UI is included in the Helm chart and enabled by default.
Access it via port-forward:

```bash
kubectl port-forward svc/temporal-web -n temporal 8080:8080
```

Open `http://localhost:8080`, switch to the `<DEPLOYMENT_NAME>-datafold`
namespace, and confirm it is listed and accessible.

---

## Alternative: Zalando Postgres Operator

If a managed database service is not an option, you can run PostgreSQL
inside the Kubernetes cluster using the
[Zalando Postgres Operator](https://postgres-operator.readthedocs.io/).
This requires more setup (operator installation, IAM for backups, custom
resources) but keeps all components within the cluster.

> **Note:** The steps below replace Steps 1–2 of the main guide. Once
> PostgreSQL is running and credentials are available, continue from
> Step 3 (Temporal install), adjusting the values file as described.

### Deployment Order (Zalando path)

| Step | Component | Notes |
|------|-----------|-------|
| A1 | Cloud storage bucket | S3 / GCS / Azure Blob for PostgreSQL backups |
| A2 | IAM / Workload Identity | Service account binding so pods can write to the bucket |
| A3 | Zalando Postgres Operator | Helm chart `postgres-operator` v1.15.1+ |
| A4 | Create Temporal namespace | `kubectl create namespace temporal` |
| A5 | PostgreSQL cluster CR | Creates `temporal-database` with two databases |
| 4  | Temporal Helm chart | Continue from Step 4 in the main guide |
| 5  | Temporal namespace | Continue from Step 5 in the main guide |

### Step A1: Create Backup Storage

Create an object storage bucket for PostgreSQL logical backups. Enable
server-side encryption and set a lifecycle policy to expire old backups
(7 days recommended).

| Cloud | Service | Example Bucket Name |
|-------|---------|---------------------|
| AWS | S3 | `<DEPLOYMENT_NAME>-postgres-backups` |
| GCP | Cloud Storage | `<DEPLOYMENT_NAME>-postgres-backups` |
| Azure | Blob Storage | Container in a Storage Account |

### Step A2: Create IAM / Workload Identity Binding

Grant the `postgres-pod` Kubernetes service account permission to read and
write to the backup bucket.

#### AWS (EKS)

Create an IAM role with an OIDC trust policy for the EKS cluster. The role
must grant the following S3 actions, restricted to the backup bucket ARN:

- Bucket-level (`arn:aws:s3:::<BUCKET>`): `s3:ListBucket`, `s3:GetBucketLocation`
- Object-level (`arn:aws:s3:::<BUCKET>/*`): `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`

#### GCP (GKE)

Create a Google Service Account (GSA) with `roles/storage.objectAdmin`.
**Scope the role binding to the backup bucket only** -- bind at the bucket
level, not at the project level. Then bind the GSA to the Kubernetes service
account via Workload Identity Federation:

```bash
gcloud iam service-accounts add-iam-policy-binding \
  <GSA_NAME>@<PROJECT_ID>.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:<PROJECT_ID>.svc.id.goog[temporal/postgres-pod]"
```

#### Azure (AKS)

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
  --subject system:serviceaccount:temporal:postgres-pod
```

### Step A3: Install Zalando Postgres Operator

The Zalando Postgres Operator manages PostgreSQL clusters as Kubernetes custom
resources. It is cluster-scoped and watches all namespaces.

```bash
helm repo add postgres-operator-charts \
  https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo update

helm upgrade --install postgres-operator postgres-operator-charts/postgres-operator \
  --namespace postgres-operator --create-namespace \
  --version 1.15.1 \
  --wait --timeout 3m
```

After installation the operator's configuration is stored in an
`OperatorConfiguration` custom resource on the cluster. Edit it in place:

```bash
kubectl edit operatorconfiguration postgres-operator -n postgres
```

Update only the `configuration.logical_backup` and `configuration.kubernetes`
sections for your cloud provider.

#### AWS (EKS)

```yaml
configuration:
  logical_backup:
    logical_backup_provider: s3
    logical_backup_s3_bucket: "<DEPLOYMENT_NAME>-postgres-backups"
    logical_backup_s3_region: "<AWS_REGION>"
    logical_backup_s3_sse: AES256
    logical_backup_schedule: "30 00 * * *"
  kubernetes:
    pod_service_account_name: postgres-pod
    pod_service_account_definition: '{"apiVersion":"v1","kind":"ServiceAccount","metadata":{"name":"postgres-pod","annotations":{"eks.amazonaws.com/role-arn":"arn:aws:iam::<ACCOUNT_ID>:role/<DEPLOYMENT_NAME>-postgres-backup"}}}'
```

#### GCP (GKE)

```yaml
configuration:
  logical_backup:
    logical_backup_provider: gcs
    logical_backup_gcs_bucket: "<DEPLOYMENT_NAME>-postgres-backups"
    logical_backup_schedule: "30 00 * * *"
  kubernetes:
    pod_service_account_name: postgres-pod
    pod_service_account_definition: '{"apiVersion":"v1","kind":"ServiceAccount","metadata":{"name":"postgres-pod","annotations":{"iam.gke.io/gcp-service-account":"<GSA_NAME>@<PROJECT_ID>.iam.gserviceaccount.com"}}}'
```

#### Azure (AKS)

```yaml
configuration:
  logical_backup:
    logical_backup_provider: az
    logical_backup_azure_storage_account_name: "<STORAGE_ACCOUNT>"
    logical_backup_azure_storage_container: "<CONTAINER_NAME>"
    logical_backup_azure_storage_account_key: "<STORAGE_KEY>"
    logical_backup_schedule: "30 00 * * *"
  kubernetes:
    pod_service_account_name: postgres-pod
    pod_service_account_definition: '{"apiVersion":"v1","kind":"ServiceAccount","metadata":{"name":"postgres-pod","labels":{"azure.workload.identity/use":"true"},"annotations":{"azure.workload.identity/client-id":"<MANAGED_IDENTITY_CLIENT_ID>"}}}'
```

### Step A4: Create the Temporal Namespace

```bash
kubectl create namespace temporal
```

### Step A5: Deploy PostgreSQL Cluster

Create a file called `temporal-database.yaml` with the following PostgreSQL
cluster custom resource. The Zalando operator will create a StatefulSet, a
Service named `temporal-database`, and Kubernetes Secrets containing the
database credentials.

```yaml
apiVersion: "acid.zalan.do/v1"
kind: postgresql
metadata:
  name: temporal-database
  namespace: temporal
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
    temporal:
      - superuser
      - createdb

  databases:
    temporal: temporal
    temporal_visibility: temporal

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

```bash
kubectl apply -f temporal-database.yaml
kubectl wait --for=condition=Ready pod/temporal-database-0 \
  -n temporal --timeout=5m
```

The operator creates a Kubernetes Secret for the database user:

| User | Secret Name | Purpose |
|------|-------------|---------|
| `temporal` | `temporal.temporal-database.credentials.postgresql.acid.zalan.do` | Database owner used by both schema init jobs and the Temporal server. |

**Volume sizing:** 20Gi is adequate for the expected workload. Temporal's
database usage scales with the number of open (in-flight) workflows and
retained history, not the total number of completed workflows.

#### Verify Backup

Before proceeding, confirm that the backup CronJob can run successfully:

```bash
kubectl create job --from=cronjob/logical-backup-temporal-database \
  logical-backup-temporal-database-manual \
  -n temporal

kubectl wait --for=condition=complete \
  job/logical-backup-temporal-database-manual \
  -n temporal --timeout=5m
```

If the job does not complete within the timeout, check the pod logs:

```bash
kubectl logs -n temporal \
  -l job-name=logical-backup-temporal-database-manual --tail=50
```

Common causes of failure are missing or misconfigured IAM permissions and an
incorrect bucket name or region in the `OperatorConfiguration`. Resolve any
errors before continuing.

Once the job shows `Complete`, clean it up:

```bash
kubectl delete job logical-backup-temporal-database-manual -n temporal
```

### Temporal Values File (Zalando path)

Use the following `temporal-values.yaml` when using the Zalando operator.
The secret name differs from the managed-database path:

```yaml
server:
  config:
    persistence:
      default:
        driver: "sql"
        sql:
          driver: "postgres12"
          host: temporal-database.temporal.svc.cluster.local
          port: 5432
          database: temporal
          user: temporal
          existingSecret: temporal.temporal-database.credentials.postgresql.acid.zalan.do
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
          host: temporal-database.temporal.svc.cluster.local
          port: 5432
          database: temporal_visibility
          user: temporal
          existingSecret: temporal.temporal-database.credentials.postgresql.acid.zalan.do
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

Then continue from **Step 4** of the main guide to install Temporal and
register the namespace.

---

## Placeholder Reference

| Placeholder | Description | Examples |
|-------------|-------------|----------|
| `<DEPLOYMENT_NAME>` | Your deployment or environment name | `acme`, `staging`, `production` |
| `<DEPLOYMENT_NAME>-datafold` | Temporal logical namespace (convention) | `acme-datafold`, `staging-datafold` |
| `<RDS_ENDPOINT>` | Hostname of the managed PostgreSQL instance | `acme-temporal.abc123.us-east-1.rds.amazonaws.com` |
| `<TEMPORAL_DB_PASSWORD>` | Password for the `temporal` database user | (generate a strong random password) |
| `<MASTER_PASSWORD>` | Master password for the managed DB instance | (set during instance creation) |
| `<CHART_VERSION>` | Temporal Helm chart version (>= 1.0.0) | `1.0.0`, `1.1.0` |
| `<STORAGE_CLASS>` | Kubernetes StorageClass for persistent volumes (Zalando path) | `gp3`, `pd-ssd`, `managed-premium` |
| `<SECURITY_GROUP_ID>` | AWS security group ID for RDS | `sg-0abc123` |
| `<SUBNET_GROUP>` | AWS RDS subnet group name | `default-vpc-abc123` |
| `<ACCOUNT_ID>` | AWS account ID | `524263733165` |
| `<AWS_REGION>` | AWS region | `us-east-1` |
| `<GCP_REGION>` | GCP region | `us-central1` |
| `<VPC_NETWORK>` | GCP VPC network name | `default` |
| `<PROJECT_ID>` | GCP project ID | `datafold-production` |
| `<GSA_NAME>` | GCP service account name for backups | `postgres-backup` |
| `<AZURE_REGION>` | Azure region | `eastus` |
| `<VNET_NAME>` | Azure virtual network name | `datafold-vnet` |
| `<SUBNET_NAME>` | Azure subnet name | `postgres-subnet` |
| `<MANAGED_IDENTITY_CLIENT_ID>` | Azure managed identity client ID | (UUID) |
| `<MANAGED_IDENTITY_NAME>` | Azure managed identity name | `postgres-backup-identity` |
| `<RESOURCE_GROUP>` | Azure resource group | `datafold-rg` |
| `<AKS_OIDC_ISSUER_URL>` | AKS cluster OIDC issuer URL | `https://oidc.prod-aks.azure.com/...` |
| `<STORAGE_ACCOUNT>` | Azure storage account name (backups) | `datafoldbackups` |
| `<CONTAINER_NAME>` | Azure blob container name (backups) | `postgres-backups` |
| `<STORAGE_KEY>` | Azure storage account key (backups) | (key string) |
