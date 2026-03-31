# KEDA: Kubernetes Event-Driven Autoscaling

Datafold's Temporal workers use [KEDA](https://keda.sh/) to scale pods based on
Temporal task queue depth. When queues are empty, workers scale to zero replicas
— no pods run and no compute is consumed. When work arrives, KEDA detects the
queue depth and scales workers up automatically.

KEDA must be installed **before** deploying the Datafold application.

> **Support scope:** KEDA is a third-party open-source component. Datafold
> provides these deployment instructions as guidance, but **Datafold's support
> is scoped to the Datafold application** that runs on top of KEDA. For issues
> with KEDA itself, refer to the [KEDA documentation](https://keda.sh/docs/).

---

## How it works

Each `worker-temporal` subchart creates a KEDA `ScaledObject` that watches one
or more Temporal task queues. The scaler polls the Temporal frontend gRPC API at
a configurable interval. When the number of pending tasks exceeds
`activationTargetQueueSize`, KEDA creates the worker pods. As tasks are
processed and the queue drains, KEDA scales the workers back down to zero after
the cooldown period elapses.

```
Temporal task queue depth
        │
        ▼
┌───────────────┐   polls every pollingInterval seconds
│  KEDA Scaler  │ ────────────────────────────────────▶ Temporal Frontend :7233
│  (temporal)   │
└───────┬───────┘
        │ adjusts
        ▼
┌───────────────────────┐
│  worker-io Deployment │  0 → N replicas
│  worker-compute       │  N → 0 after cooldown
│  worker-highmem       │  ...
│  ...                  │
└───────────────────────┘
```

---

## Deployment order

Deploy components in this order. Each step depends on the previous one. Steps
1–5 are covered in [temporal-prerequisites.md](temporal-prerequisites.md).

| Step | Component | Notes |
|------|-----------|-------|
| 1 | Managed PostgreSQL instance | AWS RDS, GCP Cloud SQL, or Azure Database |
| 2 | Database setup | Two databases, dedicated user, Kubernetes Secret |
| 3 | Create Temporal namespace | Required before deploying Temporal |
| 4 | Temporal Helm chart | Points at the managed PostgreSQL instance |
| 5 | Temporal logical namespace | One-time admin operation via `temporal-admintools` pod |
| **6** | **KEDA** | Required before deploying the Datafold application |
| 7 | Datafold application | Workers will scale via KEDA from this point on |

---

## Requirements

- Kubernetes 1.27+
- KEDA **>= 2.19.0**
- Helm 3

---

## Install KEDA

Add the KEDA Helm repository and install into its own namespace.

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
```

Install (pin to the current latest stable release):

```bash
helm upgrade --install keda kedacore/keda \
  --namespace keda \
  --create-namespace \
  --version 2.19.0
```

> **Version:** 2.19.0 is both the minimum required and the current latest stable
> release (chart version and app version are aligned). Check
> https://github.com/kedacore/charts/releases for newer versions before
> deploying to production.

---

## Verify installation

Confirm the KEDA pods are running:

```bash
kubectl get pods -n keda
```

Expected output (all pods `Running`):

```
NAME                                      READY   STATUS    RESTARTS   AGE
keda-admission-webhooks-...               1/1     Running   0          1m
keda-operator-...                         1/1     Running   0          1m
keda-operator-metrics-apiserver-...       1/1     Running   0          1m
```

Confirm the required CRDs are installed:

```bash
kubectl get crd | grep keda.sh
```

Expected CRDs:

```
clustertriggerauthentications.keda.sh
scaledjobs.keda.sh
scaledobjects.keda.sh
triggerauthentications.keda.sh
```

---

## Worker scaling configuration

Each `worker-temporal` instance exposes a `keda:` block in `values.yaml`. The
defaults are set to scale to zero and back up:

```yaml
keda:
  enabled: true                         # Set false to disable KEDA for this worker
  minReplicas: 0                        # Scale to zero when the queue is empty
  maxReplicas: 10                       # Upper replica bound
  pollingInterval: 30                   # Seconds between queue depth checks
  cooldownPeriod: 300                   # Seconds idle before scaling to 0
  targetQueueSize: "5"                  # Target pending tasks per replica
  activationTargetQueueSize: "0"        # Queue depth that triggers the first pod
  scaleDown:
    stabilizationWindowSeconds: 300     # Prevents flapping during scale-down
  authRef: ""                           # TriggerAuthentication name (see below)
```

| Field | Default | Effect |
|-------|---------|--------|
| `enabled` | `true` | Creates a `ScaledObject` for this worker. Set `false` to use a fixed `replicaCount` instead. |
| `minReplicas` | `0` | Scales to zero when the queue is empty. Set to `1` to keep a warm standby. |
| `maxReplicas` | `10` | Hard upper limit on replica count. |
| `pollingInterval` | `30` | How often (seconds) KEDA queries the Temporal queue depth. |
| `cooldownPeriod` | `300` | Seconds after the queue empties before scaling to zero begins. |
| `targetQueueSize` | `"5"` | KEDA targets this many pending tasks per replica when scaling out. |
| `activationTargetQueueSize` | `"0"` | Queue depth that must be exceeded to scale from 0 → 1. `"0"` means any task activates the worker. |
| `scaleDown.stabilizationWindowSeconds` | `300` | HPA stabilization window — prevents rapid scale-down oscillation. |
| `authRef` | `""` | Name of a `TriggerAuthentication` object. Leave empty if Temporal is not configured with authentication. |

### Per-worker overrides

Override the defaults for individual worker types in your `values.yaml`. For
example, to limit the high-memory worker to three replicas and keep one always
warm:

```yaml
worker-highmem:
  keda:
    minReplicas: 1
    maxReplicas: 3

worker-compute:
  keda:
    maxReplicas: 20
    targetQueueSize: "10"
```

---

## TriggerAuthentication (optional)

If the Temporal frontend requires authentication (mTLS, API key, or token),
create a `TriggerAuthentication` object in the same namespace as the Datafold
workers, then reference it with `authRef`.

Example for a bearer token stored in a Kubernetes Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: temporal-keda-auth
  namespace: <DATAFOLD_NAMESPACE>
type: Opaque
stringData:
  token: <TEMPORAL_API_TOKEN>
---
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: temporal-keda-triggerauth
  namespace: <DATAFOLD_NAMESPACE>
spec:
  secretTargetRef:
    - parameter: token
      name: temporal-keda-auth
      key: token
```

Then set `authRef` for the workers that need it:

```yaml
worker-io:
  keda:
    authRef: temporal-keda-triggerauth
```

Refer to the [KEDA TriggerAuthentication docs](https://keda.sh/docs/latest/concepts/authentication/)
for the full set of authentication providers supported.

---

## Upgrading KEDA

KEDA CRDs are not automatically upgraded by `helm upgrade`. When upgrading to a
new KEDA version:

1. Check the release notes for CRD changes at
   https://github.com/kedacore/charts/releases
2. Apply updated CRDs manually if required:
   ```bash
   kubectl apply -f https://github.com/kedacore/keda/releases/download/v<NEW_VERSION>/keda-<NEW_VERSION>-crds.yaml
   ```
3. Then upgrade the Helm release:
   ```bash
   helm upgrade keda kedacore/keda \
     --namespace keda \
     --version <NEW_VERSION> \
     --skip-crds
   ```

---

## Placeholder reference

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `<DATAFOLD_NAMESPACE>` | Kubernetes namespace where Datafold workers run | `datafold`, `production` |
| `<TEMPORAL_API_TOKEN>` | Bearer token for Temporal authentication | (generate a strong random value) |
| `<NEW_VERSION>` | Target KEDA version for upgrades | `2.20.0` |
