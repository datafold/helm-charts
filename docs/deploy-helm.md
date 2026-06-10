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

Switch the task engine to Temporal under `config`, and set the Temporal address
in two places:

- `config.temporalAddress` — consumed by the application (server and workers) as
  `TEMPORAL_ADDRESS`.
- `global.temporal.address` — consumed by the KEDA scaler to poll queue depth.

For self-hosted Temporal both are the in-cluster frontend service address. For
Temporal Cloud, use your cloud namespace endpoint (see
[Temporal Cloud Additions](#temporal-cloud-additions) below).

```yaml
# values.yaml (self-hosted Temporal)
config:
  taskEngine: "temporal"   # default is "celery"; set to "temporal" to switch
  temporalAddress: "temporal-frontend.temporal.svc.cluster.local:7233"

global:
  temporal:
    address: "temporal-frontend.temporal.svc.cluster.local:7233"
```

> **Note:** `global.temporal.namespace` is a **Temporal Cloud–only** override.
> For self-hosted Temporal, leave it unset — the workers use the release
> namespace (`Release.Namespace`) automatically.

---

## Enabling Temporal Workers

Each Temporal worker is an instance of the shared `worker-temporal` subchart,
toggled with `install: true` (the Helm dependency condition is
`<worker>.install`). **Each worker is preset to its own Temporal task queue and
pool type in the chart — you do not set the queue yourself.** Turn on autoscaling
per worker with `keda.enabled: true`.

| Worker | Task queue | Pool type | `install` default |
|--------|-----------|-----------|-------------------|
| `worker-io` | `io` | thread | `true` |
| `worker-compute` | `compute` | process | `true` |
| `worker-highmem` | `highmem` | process | `true` |
| `worker-storage` | `storage` | process | `true` |
| `worker-storage-high` | `storagehigh` | process | `true` |
| `worker-monitors` | `monitors` | process | `true` |

> The task queue, pool type, termination grace period, and default
> resource requests/limits for each worker are set in the chart's `values.yaml`.
> Override only what you need — typically the `keda` bounds and `resources`.
> `keda.enabled` defaults to `false`, so KEDA must be enabled explicitly per
> worker. The per-replica concurrency (`temporal.maxConcurrency`) is also the
> value KEDA targets when scaling out — there is **no** `keda.targetQueueSize`.

### worker-io (`io` queue)

```yaml
worker-io:
  install: true
  keda:
    enabled: true
    minReplicas: 1        # keep one warm replica
    maxReplicas: 10
    pollingInterval: 30   # seconds between queue-depth polls
    cooldownPeriod: 300   # seconds idle before scaling down
  temporal:
    maxConcurrency: "20"  # concurrent tasks per replica; KEDA's scale target
  resources:
    limits:
      memory: 6Gi
    requests:
      cpu: 500m
      memory: 6Gi
```

### worker-compute (`compute` queue)

```yaml
worker-compute:
  install: true
  keda:
    enabled: true
    minReplicas: 0        # scale to zero when idle
    maxReplicas: 5
  resources:
    limits:
      memory: 10Gi
    requests:
      cpu: 500m
      memory: 10Gi
```

### worker-highmem (`highmem` queue)

```yaml
worker-highmem:
  install: true
  keda:
    enabled: true
    minReplicas: 0
    maxReplicas: 3
  resources:
    limits:
      memory: 25Gi
    requests:
      cpu: 100m
      memory: 25Gi
```

### worker-storage (`storage` queue)

Storage workers attach a PersistentVolume via the `storage` block.

```yaml
worker-storage:
  install: true
  keda:
    enabled: true
    minReplicas: 0
    maxReplicas: 5
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

### worker-storage-high (`storagehigh` queue)

```yaml
worker-storage-high:
  install: true
  keda:
    enabled: true
    minReplicas: 0
    maxReplicas: 3
  storage:
    enabled: true
    dataSize: 300Gi
  resources:
    limits:
      memory: 30Gi
    requests:
      cpu: 100m
      memory: 30Gi
```

### worker-monitors (`monitors` queue)

Keep one warm replica so scheduled monitor/alert runs start without a cold start:

```yaml
worker-monitors:
  install: true
  keda:
    enabled: true
    minReplicas: 1        # keep one warm replica
    maxReplicas: 5
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

Activate Temporal under `config` as for self-hosted (see
[Activating Temporal](#activating-temporal)), then add the Temporal Cloud auth
and encryption settings under `global.temporal`:

```yaml
config:
  taskEngine: "temporal"
  temporalAddress: "<CLOUD_NAMESPACE>.tmprl.cloud:7233"

global:
  temporal:
    address: "<CLOUD_NAMESPACE>.tmprl.cloud:7233"  # used by the KEDA scaler
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
