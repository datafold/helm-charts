# Managed PostgreSQL for Temporal

Temporal requires a PostgreSQL database for persistence. The recommended approach
is to use a **managed PostgreSQL service** — AWS RDS, GCP Cloud SQL, or Azure
Database for PostgreSQL. These handle backups, high availability, and upgrades
without additional Kubernetes operators.

> **Support scope:** PostgreSQL is a third-party component. Datafold provides
> these instructions as guidance, but support is scoped to the Datafold
> application running on top of it. For PostgreSQL issues, refer to your cloud
> provider's documentation.

---

## Requirements

- **Version:** PostgreSQL 17
- **Network:** reachable from the Kubernetes cluster on port 5432 (same VPC or peered VPC)
- **Sizing:** `db.t3.medium` (2 vCPU / 4 GiB) or equivalent — adequate for the expected Datafold workload
- **Storage:** 20 GiB with autoscaling enabled

---

## Step 1: Provision the Instance

### AWS RDS

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

Allow inbound TCP 5432 from the EKS node security group in `<SECURITY_GROUP_ID>`.
Wait for `available` status:

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

Use the **Private IP** address as `<RDS_ENDPOINT>`. Ensure your GKE nodes can
route to the Cloud SQL private IP.

### Azure Database for PostgreSQL

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

Use the server's hostname as `<RDS_ENDPOINT>`.

---

## Step 2: Create Databases, User, and Kubernetes Secret

### Create the Temporal Kubernetes Namespace

```bash
kubectl create namespace temporal
```

### Create Databases and User

Connect to the managed instance as the admin user:

```sql
CREATE USER temporal WITH PASSWORD '<TEMPORAL_DB_PASSWORD>';

CREATE DATABASE temporal OWNER temporal;
CREATE DATABASE temporal_visibility OWNER temporal;

GRANT ALL PRIVILEGES ON DATABASE temporal TO temporal;
GRANT ALL PRIVILEGES ON DATABASE temporal_visibility TO temporal;
```

> **AWS RDS note:** The master user is not a true superuser. After connecting to
> each database, also run:
>
> ```sql
> GRANT ALL ON SCHEMA public TO temporal;
> ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO temporal;
> ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO temporal;
> ```

### Store Credentials in Kubernetes

```bash
kubectl create secret generic temporal-db-credentials \
  --namespace temporal \
  --from-literal=password=<TEMPORAL_DB_PASSWORD>
```

The key name must be `password` — this is what the Temporal Helm chart's
`existingSecret` field references.

---

## Next Step

Continue with [Temporal Helm chart installation](temporal-install.md).

---

## Placeholder Reference

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `<DEPLOYMENT_NAME>` | Your deployment name | `acme`, `production` |
| `<RDS_ENDPOINT>` | Managed PostgreSQL hostname | `acme-temporal.abc123.us-east-1.rds.amazonaws.com` |
| `<TEMPORAL_DB_PASSWORD>` | Password for the `temporal` DB user | (generate a strong random password) |
| `<MASTER_PASSWORD>` | Admin password set during instance creation | |
| `<SECURITY_GROUP_ID>` | AWS security group for RDS inbound | `sg-0abc123` |
| `<SUBNET_GROUP>` | AWS RDS subnet group | `default-vpc-abc123` |
| `<AWS_REGION>` | AWS region | `us-east-1` |
| `<GCP_REGION>` | GCP region | `us-central1` |
| `<VPC_NETWORK>` | GCP VPC network name | `default` |
| `<AZURE_REGION>` | Azure region | `eastus` |
| `<VNET_NAME>` | Azure virtual network | `datafold-vnet` |
| `<SUBNET_NAME>` | Azure subnet | `postgres-subnet` |
| `<RESOURCE_GROUP>` | Azure resource group | `datafold-rg` |

---

## Next Step

Continue with **[Temporal Helm chart installation](temporal-install.md)**.
