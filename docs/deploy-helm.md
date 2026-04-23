# Deploy Datafold with Direct Helm Values (Alternative)

This method installs Datafold by passing a `values.yaml` file directly to
`helm install` or `helm upgrade`. It is provided for environments where the
Datafold operator cannot be used.

> **Prefer the operator.** Helm does not validate values files. A typo in a
> field name, an incorrect nesting level, or a missing required value will be
> silently accepted by Helm and only fail at runtime — often with a confusing
> error far removed from the configuration mistake. The
> [operator method](deploy-operator.md) rejects invalid configuration at apply
> time with a clear error message.

Complete [prerequisites](prerequisites.md) before starting.

> **Note:** This guide covers new Temporal-based deployments. Migrating an
> existing Celery-based deployment to Temporal is a separate process not
> covered here.

---

## Activating Temporal

Set `global.taskEngine` to `temporal` and configure the Temporal address. For
self-hosted Temporal, that is the in-cluster service address. For Temporal Cloud,
use your cloud namespace endpoint.

```yaml
# values.yaml (self-hosted Temporal)
global:
  taskEngine: "temporal"
  temporal:
    address: "temporal-frontend.temporal.svc.cluster.local:7233"
    namespace: "<DEPLOYMENT_NAME>-datafold"
```

---

## Enabling Temporal Workers

Each Temporal worker type runs as a separate Helm subchart. All are disabled by
default. Enable the ones you need and configure KEDA to scale them automatically.

### worker-io (I/O worker — datadiff queue)

```yaml
worker-io:
  enabled: true
  temporal:
    taskQueues: "datadiff"
  keda:
    enabled: true
    minReplicas: 1        # keep one warm replica
    maxReplicas: 10
    pollingInterval: 30
    cooldownPeriod: 300
    targetQueueSize: "5"
  resources:
    limits:
      memory: 4Gi
    requests:
      cpu: 200m
      memory: 4Gi
```

### worker-compute (compute-intensive — datadiff, translation queues)

```yaml
worker-compute:
  enabled: true
  temporal:
    taskQueues: "datadiff,translation"
  keda:
    enabled: true
    minReplicas: 0        # scale to zero when idle
    maxReplicas: 5
    pollingInterval: 30
    cooldownPeriod: 300
    targetQueueSize: "5"
  extraEnv:
    - name: TEMPORAL_CODEC_ENCRYPTION
      value: "false"      # disable payload encryption for this worker if needed
  resources:
    limits:
      memory: 8Gi
    requests:
      cpu: 500m
      memory: 8Gi
```

### worker-highmem (high-memory — lineage, catalog queues)

```yaml
worker-highmem:
  enabled: true
  temporal:
    taskQueues: "lineage,catalog"
  keda:
    enabled: true
    minReplicas: 0
    maxReplicas: 3
    targetQueueSize: "5"
  resources:
    limits:
      memory: 20Gi
    requests:
      cpu: 100m
      memory: 20Gi
```

### worker-realtime (interactive, api queues)

```yaml
worker-realtime:
  enabled: true
  temporal:
    taskQueues: "interactive,api"
  keda:
    enabled: true
    minReplicas: 1        # keep one warm for interactive latency
    maxReplicas: 5
    targetQueueSize: "5"
  resources:
    limits:
      memory: 4Gi
    requests:
      cpu: 200m
      memory: 4Gi
```

### worker-storage (localstorage, replication queues)

```yaml
worker-storage:
  enabled: true
  temporal:
    taskQueues: "localstorage,replication"
  keda:
    enabled: true
    minReplicas: 0
    maxReplicas: 5
    targetQueueSize: "5"
  storage:
    enabled: true
    dataSize: 100Gi
  resources:
    limits:
      memory: 15Gi
    requests:
      cpu: 100m
      memory: 15Gi
```

### worker-storage-high (large localstorage queue)

```yaml
worker-storage-high:
  enabled: true
  temporal:
    taskQueues: "localstorage-large"
  keda:
    enabled: true
    minReplicas: 0
    maxReplicas: 3
    targetQueueSize: "5"
  storage:
    enabled: true
    dataSize: 200Gi
  resources:
    limits:
      memory: 30Gi
    requests:
      cpu: 100m
      memory: 30Gi
```

---

## Server Environment Variables

The `server` subchart accepts extra environment variables via the `env` key
(not `extraEnv`):

```yaml
server:
  env:
    - name: SOME_FEATURE_FLAG
      value: "true"
    - name: MY_SECRET_VALUE
      valueFrom:
        secretKeyRef:
          name: my-secret
          key: myKey
```

---

## Temporal Cloud Additions

For Temporal Cloud, add the auth and encryption settings under `global.temporal`:

```yaml
global:
  taskEngine: "temporal"
  temporal:
    address: "<CLOUD_NAMESPACE>.tmprl.cloud:7233"
    namespace: "<CLOUD_NAMESPACE>"      # e.g. "acme-datafold.abc123"
    apiKey: "<TEMPORAL_CLOUD_API_KEY>"  # store this in a Kubernetes Secret if possible
    corsOrigins: "https://cloud.temporal.io"
    encryption:
      keys:
        - id: KEY_1
          value: "<BASE64_AES256_KEY>"  # openssl rand -base64 32
        - id: KEY_0
          value: "<BASE64_AES256_KEY>"  # previous key for rotation
      activeKeyId: KEY_1
```

For custom codec class (e.g. AWS KMS), also set:

```yaml
global:
  temporal:
    encryption:
      codecClass: "temporal_codec:KMSCodec"
      customCodec:
        configMapName: acme-temporal-codec
        fileName: temporal_codec.py
```

See [temporal-cloud-encryption.md](temporal-cloud-encryption.md) for how to
create the ConfigMap with your custom Python codec implementation.

---

## Install / Upgrade

```bash
helm upgrade --install datafold datafold/datafold \
  --namespace <YOUR_NAMESPACE> \
  --values values.yaml \
  --version <CHART_VERSION>
```

---

## Placeholder Reference

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `<DEPLOYMENT_NAME>` | Your deployment name | `acme`, `production` |
| `<CLOUD_NAMESPACE>` | Temporal Cloud namespace | `acme-datafold.abc123` |
| `<TEMPORAL_CLOUD_API_KEY>` | API key from Temporal Cloud console | |
| `<BASE64_AES256_KEY>` | Base64-encoded 32-byte AES key | `openssl rand -base64 32` |
| `<YOUR_NAMESPACE>` | Kubernetes namespace for Datafold | `datafold` |
| `<CHART_VERSION>` | Datafold Helm chart version | `1.2.11` |
