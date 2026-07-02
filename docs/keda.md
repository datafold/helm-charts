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
1–5 are covered in the [prerequisites guide](prerequisites.md).

| Step | Component | Notes |
|------|-----------|-------|
| 1 | PostgreSQL | [Managed DB](postgres-rds.md) or [Zalando in-cluster](postgres-zalando.md) |
| 2 | Database setup | Two databases, dedicated user, Kubernetes Secret |
| 3 | Temporal Helm chart | [temporal-install.md](temporal-install.md) |
| 4 | Temporal logical namespace | One-time admin operation via `temporal-admintools` pod |
| **5** | **KEDA** | Required before deploying the Datafold application |
| 6 | Datafold application | Workers will scale via KEDA from this point on |

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

Each `worker-temporal` instance exposes a `keda:` block in `values.yaml`. KEDA
is **disabled by default** — enable it per worker with `keda.enabled: true`.
The shipped defaults are:

```yaml
keda:
  enabled: false                        # Set true to create a ScaledObject for this worker
  minReplicas: 0                        # Scale to zero when the queue is empty
  maxReplicas: 10                       # Upper replica bound
  pollingInterval: 30                   # Seconds between queue depth checks
  cooldownPeriod: 300                   # Seconds idle before scaling to 0
  targetQueueSize: ""                   # Queued tasks per pod the HPA aims for (empty → maxConcurrency)
  activationTargetQueueSize: "0"        # Queue depth that triggers the first pod
  queueTypes: ""                        # Task types counted in the backlog ("activity", "workflow", or both)
  scaleDown:
    stabilizationWindowSeconds: 300     # Prevents flapping during scale-down
    policies: []                        # Optional HPA v2 scale-down rate policies
  fallback: {}                          # Hold a fixed replica count when a scaler errors
  prometheusTriggers: []                # Extra prometheus triggers (e.g. in-flight-slots hold)
  authRef: ""                           # TriggerAuthentication name (see below)
```

| Field | Default | Effect |
|-------|---------|--------|
| `enabled` | `false` | Creates a `ScaledObject` for this worker. While `false`, the worker runs at a fixed `replicaCount`. |
| `minReplicas` | `0` | Scales to zero when the queue is empty. Set to `1` to keep a warm standby. |
| `maxReplicas` | `10` | Hard upper limit on replica count. |
| `pollingInterval` | `30` | How often (seconds) KEDA queries the Temporal queue depth. |
| `cooldownPeriod` | `300` | Seconds after the queue empties before scaling to zero begins. |
| `targetQueueSize` | `""` | Queued tasks per pod the HPA targets: `desired = ceil(backlog / targetQueueSize)`. Empty inherits `temporal.maxConcurrency` — fine for fast tasks, but for long-running activities even a short queue means a long wait, so set it lower (e.g. `"1"`–`"2"`). |
| `activationTargetQueueSize` | `"0"` | Queue depth that must be exceeded to scale from 0 → 1. `"0"` means any task activates the worker. |
| `queueTypes` | `""` | Which Temporal task types count toward the backlog (`"activity"`, `"workflow"`, or both comma-separated). Empty uses the KEDA scaler default, which is version-dependent — pin it when the distinction matters. |
| `scaleDown.stabilizationWindowSeconds` | `300` | HPA stabilization window — prevents rapid scale-down oscillation. |
| `scaleDown.policies` | `[]` | HPA v2 scale-down rate policies, passed through verbatim (e.g. `{type: Pods, value: 1, periodSeconds: 600}` sheds at most one pod per 10 minutes). |
| `fallback` | `{}` | KEDA `spec.fallback` (`failureThreshold` + `replicas`): hold a fixed replica count after a scaler errors repeatedly. Applies to `AverageValue` metrics such as `prometheusTriggers`. |
| `prometheusTriggers` | `[]` | Additional `type: prometheus` triggers; the HPA scales to the max desired across all triggers. See below. |
| `authRef` | `""` | Name of a `TriggerAuthentication` object. Leave empty if Temporal is not configured with authentication. |

> **Scale-out target.** `keda.targetQueueSize` controls how aggressively a
> worker scales out. When left empty it inherits `temporal.maxConcurrency` —
> the number of concurrent tasks one replica handles — which suits fast tasks.

### Prometheus triggers (in-flight-slots hold)

The Temporal backlog only measures *waiting* work, not *busy* work. A worker
running long activities can look idle to the backlog trigger (queue empty)
while every slot is occupied for hours — and gets scaled down mid-work. A
`prometheusTriggers` entry adds a second signal so capacity is held while work
is in flight:

```yaml
worker-thunderbolt:
  keda:
    prometheusTriggers:
      - name: slots-hold
        serverAddress: http://datafold-prometheus:9090
        query: sum(temporal_worker_task_slots_used{task_queue="thunderbolt",worker_type="ActivityWorker"})
        threshold: "6"              # target in-flight activities per pod
        metricType: AverageValue    # desired = ceil(total_slots_used / threshold)
```

The HPA takes the **max** desired replicas across all triggers, so the backlog
trigger handles scale-up bursts and the slots trigger prevents premature
scale-down. Requires a Prometheus reachable at `serverAddress` that scrapes the
workers' `:9090` metrics endpoint. Not supported on workers polling multiple
`taskQueues` — the composite `scalingModifiers` formula those use would
silently ignore extra triggers, so the template fails fast instead.

### Per-worker overrides

Override the defaults for individual worker types in your `values.yaml`. For
example, to limit the high-memory worker to three replicas and keep one always
warm, and to let the compute worker scale wider:

```yaml
worker-highmem:
  keda:
    enabled: true
    minReplicas: 1
    maxReplicas: 3

worker-compute:
  keda:
    enabled: true
    maxReplicas: 20
  temporal:
    maxConcurrency: "10"
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
