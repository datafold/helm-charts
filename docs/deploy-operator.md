# Deploy Datafold with the Operator (Preferred)

The Datafold operator manages the full application lifecycle via a
`DatafoldApplication` Custom Resource (CR). When you apply the CR, the operator
validates it against a strict schema, deploys all components, and continuously
reconciles the cluster to match your declared state.

> **Note:** This guide covers new Temporal-based deployments. Migrating an
> existing Celery-based deployment to Temporal is a separate process not
> covered here.

---

## Step 1: Install Temporal

Follow the [Temporal hosting guide](temporal-hosting.md) to choose between
self-hosted and Temporal Cloud, then complete the installation before
continuing. Your choice determines which fields to set in Step 4.

---

## Step 2: Install the Datafold Operator

### Add the Helm repository

```bash
helm repo add datafold https://datafold.github.io/helm-charts
helm repo update
```

### Create the image pull secret

The operator image is hosted in a private Google Artifact Registry. Datafold
provides a `datafold-docker-secret.yaml` manifest as part of the customer
onboarding package. Apply it to the namespace where Datafold will be deployed
before installing the chart:

```bash
kubectl apply -f datafold-docker-secret.yaml -n <YOUR_NAMESPACE>
```

### Install the chart

```bash
helm upgrade --install datafold-manager datafold/datafold-manager \
  --namespace <YOUR_NAMESPACE> \
  --version <CHART_VERSION>
```

Verify the operator pod is running before continuing:

```bash
kubectl get pods -n <YOUR_NAMESPACE> -l app.kubernetes.io/name=datafold-manager
```

---

## Step 3: Apply the Operator Secrets

The `DatafoldApplication` CR references a single Kubernetes Secret
(`datafold-operator-secrets` by convention) that holds all sensitive values.
Datafold provides a pre-populated `datafold-operator-secrets.yaml` manifest as
part of the customer onboarding package. Apply it to the same namespace as the
operator:

```bash
kubectl apply -f datafold-operator-secrets.yaml -n <YOUR_NAMESPACE>
```

---

## Step 4: Configure the DatafoldApplication CR

### Self-Hosted Temporal

Use the annotated example as your starting point:
[`acme-selfhosted-temporal.yaml`](../examples/operator/acme-selfhosted-temporal.yaml)

Key fields for self-hosted Temporal:

```yaml
spec:
  global:
    taskEngine: temporal
    temporalAddress: "temporal-frontend.temporal.svc.cluster.local:7233"
    # Do not set global.temporal — that section is for Temporal Cloud only
```

All Temporal workers are enabled and scaled by KEDA:

```yaml
  components:
    worker-io:
      enabled: true
      keda:
        enabled: true
        minReplicas: 1     # keep one warm replica for low-latency response
    worker-compute:
      enabled: true
      keda:
        enabled: true      # scales to zero when queues are empty
    worker-highmem:
      enabled: true
      keda:
        enabled: true
    worker-realtime:
      enabled: true
      keda:
        enabled: true
        minReplicas: 1
    worker-storage:
      enabled: true
      keda:
        enabled: true
    worker-storage-high:
      enabled: true
      keda:
        enabled: true
```

### Temporal Cloud — Built-in Encryption

Use the annotated example as your starting point:
[`acme-temporal-cloud.yaml`](../examples/operator/acme-temporal-cloud.yaml)

Key fields for Temporal Cloud:

```yaml
spec:
  global:
    taskEngine: temporal
    temporalAddress: "<CLOUD_NAMESPACE>.tmprl.cloud:7233"
    temporal:
      namespace: "<CLOUD_NAMESPACE>"        # e.g. "acme-datafold.abc123"
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

Generate an AES-256-GCM key with:

```bash
openssl rand -base64 32
```

Store it in the secret referenced by `valueSecret`.

### Temporal Cloud — Custom Codec (KMS or other external key management)

If you need to integrate with AWS KMS or another external key provider, supply
a custom Python codec class. See:

- Example CR: [`acme-temporal-cloud-custom-codec.yaml`](../examples/operator/acme-temporal-cloud-custom-codec.yaml)
- Codec implementation guide: [temporal-cloud-encryption.md](temporal-cloud-encryption.md)

```yaml
spec:
  global:
    temporal:
      corsOrigins: "https://cloud.temporal.io"
      encryption:
        codecClass: "temporal_codec:KMSCodec"
        customCodec:
          configMapName: acme-temporal-codec
          fileName: temporal_codec.py
```

---

## Step 5: Apply the CR

```bash
kubectl apply -f acme-selfhosted-temporal.yaml
# (or whichever file you prepared)
```

The operator validates the CR schema on apply. If any field is incorrect, you
will see an error immediately. Once applied, the operator deploys all components
and begins reconciling.

Watch the rollout:

```bash
kubectl get datafoldapplication -n <YOUR_NAMESPACE> -w
```

---

## Verifying Workers

Once the deployment is running, confirm that KEDA ScaledObjects are created for
each Temporal worker:

```bash
kubectl get scaledobjects -n <YOUR_NAMESPACE>
```

You should see one ScaledObject per enabled Temporal worker. With no work in the
queues, workers scale to zero (or to `minReplicas` if set). Send a Temporal
workflow to see them scale up.

---

## Placeholder Reference

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `<YOUR_NAMESPACE>` | Kubernetes namespace for Datafold | `datafold`, `acme-datafold` |
| `<CHART_VERSION>` | datafold-manager chart version to install | `0.1.105` |
| `<CLOUD_NAMESPACE>` | Temporal Cloud namespace identifier | `acme-datafold.abc123` |
