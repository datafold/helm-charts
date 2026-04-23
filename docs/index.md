# Datafold Temporal Deployment

Datafold uses [Temporal](https://temporal.io/) for workflow orchestration — data
diffs, lineage computations, and pipeline execution all run as Temporal workflows
and activities. This documentation covers how to deploy Datafold with Temporal
on Kubernetes.

---

## Choose a Deployment Method

There are two ways to deploy Datafold:

| Method | Description | Validation |
|--------|-------------|------------|
| **[Operator (preferred)](deploy-operator.md)** | Apply a `DatafoldApplication` custom resource managed by the Datafold operator | CR schema is validated at apply time — misconfigured fields are rejected with a clear error |
| **[Direct Helm (alternative)](deploy-helm.md)** | Pass a `values.yaml` file directly to `helm install` | Helm does not validate values — typos and structural errors fail silently at runtime |

**The operator method is strongly recommended.** The `DatafoldApplication`
Custom Resource is validated against a strict specification when you apply it,
so configuration mistakes surface immediately with actionable error messages
rather than as mysterious runtime failures. The operator also reconciles
continuously: changes to the CR are applied automatically, and the cluster state
is kept in sync with what you declared.

The direct Helm method is provided for environments where the operator cannot be
used. It requires extra care to get values correct.

---

## Before You Start

Complete all [prerequisites](prerequisites.md) before deploying the Datafold
application:

1. **Temporal** — choose one:
   - [Self-hosted Temporal](temporal-install.md) — requires you to also deploy
     [PostgreSQL](postgres-rds.md) (managed) or [Zalando in-cluster](postgres-zalando.md)
     as the Temporal backing database
   - [Temporal Cloud](temporal-hosting.md) — fully managed; **no PostgreSQL deployment needed**
2. **KEDA** — [required for worker autoscaling](keda.md)

---

## Deployment Guides

- [Deploy with the Operator](deploy-operator.md) — preferred
- [Deploy with direct Helm values](deploy-helm.md) — alternative

---

## Reference

- [Prerequisites overview](prerequisites.md)
- [Temporal hosting: self-hosted vs Temporal Cloud](temporal-hosting.md)
- [KEDA worker autoscaling](keda.md)
- [Temporal Cloud payload encryption](temporal-cloud-encryption.md)
