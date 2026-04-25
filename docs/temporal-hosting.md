# Temporal Hosting: Self-Hosted vs Temporal Cloud

Before deploying Datafold with Temporal, you need to decide where Temporal
itself runs. There are two options.

---

## Self-Hosted Temporal

You deploy and operate the Temporal server inside your own Kubernetes cluster
using the [Temporal Helm chart](temporal-install.md). This requires a PostgreSQL
database for persistence.

**Datafold's workflows and activities are generally low-volume** — a
single-replica Temporal deployment is sufficient and straightforward to run.
Self-hosted is the right choice if you want to keep everything within your
own infrastructure boundary.

**Operational responsibilities:** upgrades, backups (via PostgreSQL), and
monitoring are yours. Datafold provides deployment instructions, but support
is scoped to the Datafold application layer.

---

## Temporal Cloud

[Temporal Cloud](https://temporal.io/cloud) is a fully managed Temporal service
operated by Temporal Technologies Inc. You provision a namespace and connect to
it via API key or mTLS — no server deployment required.

The tradeoff: workflow execution data (task payloads) leaves your cluster and
flows through Temporal's infrastructure. To address this, Datafold's built-in
**payload encryption** encrypts all workflow inputs and outputs with AES-256-GCM
keys that never leave your environment. Temporal's servers see only ciphertext.
For deployments that require custom key management (e.g. AWS KMS envelope
encryption), a [custom codec plugin](temporal-cloud-encryption.md) can be
supplied.

**When Temporal Cloud makes sense:**
- You want to eliminate the operational burden of running Temporal
- Your organisation already uses Temporal Cloud for other workloads
- You need multi-region Temporal availability

---

## Comparison

| | Self-hosted | Temporal Cloud |
|-|-------------|----------------|
| Infrastructure to operate | Temporal Helm chart + PostgreSQL | None |
| Workflow data location | Stays in your cluster | Temporal Cloud (encrypted payloads) |
| Payload encryption | Optional | Required (enforced by Datafold config) |
| Authentication | None (in-cluster) | API key or mTLS |
| Setup complexity | Moderate | Low |
| Cost | Compute + storage | Temporal Cloud subscription |

---

## Self-Hosted Configuration

When using self-hosted Temporal, `global.taskEngine: temporal` is the only
required addition beyond a running Temporal server. Leave `global.temporal`
unset (it is for Temporal Cloud settings).

```yaml
# In your DatafoldApplication CR (operator) or Helm values
global:
  taskEngine: temporal
  temporalAddress: "temporal-frontend.temporal.svc.cluster.local:7233"
```

See the [self-hosted example CR](../examples/acme-selfhosted-temporal.yaml)
for a full working configuration.

---

## Temporal Cloud Configuration

For Temporal Cloud you need the namespace identifier and an API key. If you also
enable payload encryption (strongly recommended), you provide one or more
AES-256-GCM keys stored in Kubernetes Secrets.

```yaml
# In your DatafoldApplication CR (operator)
global:
  taskEngine: temporal
  temporalAddress: "<CLOUD_NAMESPACE>.tmprl.cloud:7233"
  temporal:
    namespace: "<CLOUD_NAMESPACE>"
    apiKey:
      secretName: datafold-operator-secrets
      keyName: temporalApiKey
    corsOrigins: "https://cloud.temporal.io"
    encryption:
      activeKeyId: KEY_1
      keys:
        - id: KEY_1
          valueSecret:
            secretName: datafold-operator-secrets
            keyName: temporalEncryptionKeyV1
        - id: KEY_0
          valueSecret:
            secretName: datafold-operator-secrets
            keyName: temporalEncryptionKeyV0
```

See the [Temporal Cloud example CR](../examples/acme-temporal-cloud.yaml)
for a full working configuration, and
[temporal-cloud-encryption.md](temporal-cloud-encryption.md) for custom codec
(e.g. KMS) setup.

---

## Next Step

Once you have chosen your hosting model, proceed to the deployment guide:

- [Deploy with the Operator (preferred)](deploy-operator.md)
- [Deploy with direct Helm values (alternative)](deploy-helm.md)
