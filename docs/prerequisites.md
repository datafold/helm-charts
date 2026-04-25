# Prerequisites

The following components must be deployed and healthy **before** deploying the
Datafold application with Temporal. Each step depends on the previous one.

| Step | Component | Guide |
|------|-----------|-------|
| 1 | PostgreSQL | [Managed RDS / Cloud SQL / Azure DB](postgres-rds.md) or [Zalando in-cluster](postgres-zalando.md) |
| 2 | Temporal server | [Temporal Helm chart installation](temporal-install.md) |
| 3 | KEDA | [KEDA installation](keda.md) |
| 4 | Datafold application | [Deploy with Operator](deploy-operator.md) or [Deploy with Helm](deploy-helm.md) |

---

## PostgreSQL

Temporal stores all workflow state in PostgreSQL. You need two databases
(`temporal` and `temporal_visibility`) and a dedicated user before installing
Temporal.

Choose the option that fits your environment:

- **[Managed PostgreSQL](postgres-rds.md)** — AWS RDS, GCP Cloud SQL, or Azure
  Database for PostgreSQL. Recommended: backups, HA, and version upgrades are
  handled by the cloud provider.
- **[Zalando Postgres Operator](postgres-zalando.md)** — runs PostgreSQL as a
  Kubernetes StatefulSet inside the cluster. Suitable when a managed database
  service is not available, but requires additional setup for backup IAM.

---

## Temporal

[Temporal](https://temporal.io/) is the workflow orchestration engine that
Datafold uses to run data pipelines, diffs, and lineage computations. Before
installing Temporal, decide on your hosting model:

- **Self-hosted** — deploy the Temporal Helm chart in your cluster (covered in
  [temporal-install.md](temporal-install.md)).
- **Temporal Cloud** — use Temporal's managed service. No server to deploy, but
  additional authentication and encryption configuration is required in the
  Datafold application. See [temporal-hosting.md](temporal-hosting.md) for the
  comparison.

---

## KEDA

[KEDA](https://keda.sh/) (Kubernetes Event-Driven Autoscaling) scales Datafold's
Temporal workers up and down based on task queue depth. When queues are empty,
workers scale to zero — no idle compute cost. KEDA must be installed before
deploying Datafold workers.

See [keda.md](keda.md) for installation and configuration.

---

## Notes

- These prerequisites are for **new Temporal-based deployments**. Migrating an
  existing Celery-based Datafold deployment to Temporal is a separate process
  not covered here.
- Datafold's support is scoped to the Datafold application itself. Temporal,
  PostgreSQL, and KEDA are third-party open-source components — refer to their
  upstream documentation for issues with those layers.
