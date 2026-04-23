# Zalando Postgres Operator (In-Cluster PostgreSQL)

If a managed database service is not an option, you can run PostgreSQL inside
the Kubernetes cluster using the
[Zalando Postgres Operator](https://postgres-operator.readthedocs.io/). This
keeps all components within the cluster but requires more setup: operator
installation, IAM for backups, and custom resources.

> **Support scope:** The Zalando Postgres Operator is a third-party open-source
> component. Datafold provides these instructions as guidance, but support is
> scoped to the Datafold application. For operator issues, refer to the
> [Zalando Postgres Operator documentation](https://postgres-operator.readthedocs.io/).

---

## Deployment Order

| Step | Component | Notes |
|------|-----------|-------|
| A1 | Cloud storage bucket | S3 / GCS / Azure Blob for PostgreSQL backups |
| A2 | IAM / Workload Identity | Service account binding so pods can write to the bucket |
| A3 | Zalando Postgres Operator | Helm chart `postgres-operator` v1.15.1+ |
| A4 | Create Temporal namespace | `kubectl create namespace temporal` |
| A5 | PostgreSQL cluster CR | Creates `temporal-database` with two databases |
| — | Continue | [Temporal Helm chart installation](temporal-install.md) |

---

## Step A1: Create Backup Storage

Create an object storage bucket for PostgreSQL logical backups. Enable
server-side encryption and set a lifecycle policy to expire old backups
(7 days recommended).

| Cloud | Service | Example bucket name |
|-------|---------|---------------------|
| AWS | S3 | `<DEPLOYMENT_NAME>-postgres-backups` |
| GCP | Cloud Storage | `<DEPLOYMENT_NAME>-postgres-backups` |
| Azure | Blob Storage | Container in a Storage Account |

---

## Step A2: Create IAM / Workload Identity Binding

Grant the `postgres-pod` Kubernetes service account permission to read and
write to the backup bucket.

### AWS (EKS)

Create an IAM role with an OIDC trust policy for the EKS cluster. The role must
grant the following S3 actions, restricted to the backup bucket ARN:

- Bucket-level (`arn:aws:s3:::<BUCKET>`): `s3:ListBucket`, `s3:GetBucketLocation`
- Object-level (`arn:aws:s3:::<BUCKET>/*`): `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`

### GCP (GKE)

Create a Google Service Account (GSA) with `roles/storage.objectAdmin` scoped
to the backup bucket (bind at the bucket level, not the project level). Then
bind the GSA to the Kubernetes service account via Workload Identity Federation:

```bash
gcloud iam service-accounts add-iam-policy-binding \
  <GSA_NAME>@<PROJECT_ID>.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:<PROJECT_ID>.svc.id.goog[temporal/postgres-pod]"
```

### Azure (AKS)

Create a Managed Identity with `Storage Blob Data Contributor` scoped to the
backup container (not the subscription or resource group). Create a federated
credential for the AKS cluster:

```bash
az identity federated-credential create \
  --name postgres-pod-fedcred \
  --identity-name <MANAGED_IDENTITY_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --issuer <AKS_OIDC_ISSUER_URL> \
  --subject system:serviceaccount:temporal:postgres-pod
```

---

## Step A3: Install Zalando Postgres Operator

```bash
helm repo add postgres-operator-charts \
  https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo update
helm search repo postgres-operator-charts/postgres-operator --versions

helm upgrade --install postgres-operator postgres-operator-charts/postgres-operator \
  --namespace postgres-operator --create-namespace \
  --version 1.15.1 \
  --wait --timeout 3m
```

After installation, edit the operator configuration in place:

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

---

## Step A4: Create the Temporal Namespace

```bash
kubectl create namespace temporal
```

---

## Step A5: Deploy the PostgreSQL Cluster

Create `temporal-database.yaml`:

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
provider (`gp3` for AWS, `pd-ssd` for GCP, `managed-premium` for Azure).

```bash
kubectl apply -f temporal-database.yaml
kubectl wait --for=condition=Ready pod/temporal-database-0 \
  -n temporal --timeout=5m
```

The operator creates a Kubernetes Secret for the database user:

| User | Secret name |
|------|-------------|
| `temporal` | `temporal.temporal-database.credentials.postgresql.acid.zalan.do` |

**Volume sizing:** 20 GiB is adequate. Temporal's database usage scales with
open (in-flight) workflows, not the total count of completed workflows.

### Verify Backup

Before continuing, confirm that the backup CronJob succeeds:

```bash
kubectl create job --from=cronjob/logical-backup-temporal-database \
  logical-backup-temporal-database-manual \
  -n temporal

kubectl wait --for=condition=complete \
  job/logical-backup-temporal-database-manual \
  -n temporal --timeout=5m
```

If it times out, check the pod logs:

```bash
kubectl logs -n temporal \
  -l job-name=logical-backup-temporal-database-manual --tail=50
```

Common causes: missing IAM permissions, incorrect bucket name or region in the
`OperatorConfiguration`. Resolve any errors before continuing.

Clean up the manual job:

```bash
kubectl delete job logical-backup-temporal-database-manual -n temporal
```

---

## Placeholder Reference

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `<DEPLOYMENT_NAME>` | Your deployment name | `acme`, `production` |
| `<STORAGE_CLASS>` | Kubernetes StorageClass for PVs | `gp3`, `pd-ssd`, `managed-premium` |
| `<ACCOUNT_ID>` | AWS account ID | `123456789012` |
| `<AWS_REGION>` | AWS region | `us-east-1` |
| `<PROJECT_ID>` | GCP project ID | `my-project` |
| `<GSA_NAME>` | GCP service account for backups | `postgres-backup` |
| `<MANAGED_IDENTITY_CLIENT_ID>` | Azure managed identity client ID | (UUID) |
| `<MANAGED_IDENTITY_NAME>` | Azure managed identity name | `postgres-backup-identity` |
| `<RESOURCE_GROUP>` | Azure resource group | `datafold-rg` |
| `<AKS_OIDC_ISSUER_URL>` | AKS cluster OIDC issuer URL | `https://oidc.prod-aks.azure.com/...` |
| `<STORAGE_ACCOUNT>` | Azure storage account name | `datafoldbackups` |
| `<CONTAINER_NAME>` | Azure blob container name | `postgres-backups` |
| `<STORAGE_KEY>` | Azure storage account key | |

---

## Next Step

Continue with **[Temporal Helm chart installation](temporal-install.md)**.
