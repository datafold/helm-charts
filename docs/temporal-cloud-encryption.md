# Temporal Cloud Payload Encryption

When Datafold runs against [Temporal Cloud](temporal-hosting.md#temporal-cloud),
workflow inputs and outputs (task payloads) leave your cluster and are stored by
Temporal. Datafold encrypts those payloads **before** they leave the cluster so
Temporal's servers only ever see ciphertext.

There are two ways to provide encryption:

1. **Built-in AES-256-GCM codec** — you supply one or more 32-byte AES keys.
   Datafold's built-in codec handles encryption and decryption. This is the
   default and covers most deployments.
2. **Custom codec class** — you supply a Python class that implements the
   `temporalio.converter.PayloadCodec` interface, for example to delegate to AWS
   KMS or another external key-management service. This page covers that path.

> **Encryption is a Temporal Cloud concern.** For self-hosted Temporal the
> payloads never leave your cluster, so encryption is optional. See
> [Temporal hosting](temporal-hosting.md) for the comparison.

---

## Option 1: Built-in AES-256-GCM keys

Generate a key:

```bash
openssl rand -base64 32
```

Provide it under `global.temporal.encryption`. Each key has an arbitrary `id`
and the base64 value; `activeKeyId` selects which key encrypts **new** payloads.
Keep older keys listed so previously written payloads can still be decrypted —
this is how key rotation works.

### Helm

```yaml
global:
  temporal:
    corsOrigins: "https://cloud.temporal.io"
    encryption:
      activeKeyId: KEY_1
      keys:
        - id: KEY_1
          value: "<BASE64_AES256_KEY>"   # current key
        - id: KEY_0
          value: "<BASE64_AES256_KEY>"   # previous key, kept for decryption
```

### Operator

Store the key values in the `datafold-operator-secrets` Secret and reference
them:

```yaml
spec:
  global:
    temporal:
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

These render into a Kubernetes Secret as `TEMPORAL_ENCRYPTION_KEY_<n>` entries
(value `"<id>:<value>"`) and a `TEMPORAL_ENCRYPTION_ACTIVE_KEY_ID` config entry,
which are mounted into the server and every `worker-temporal` pod.

> **Externally-managed keys.** If a tool like the External Secrets Operator
> already creates a Secret with `TEMPORAL_ENCRYPTION_KEY_*` entries, set
> `global.temporal.encryption.externalSecretName` to that Secret's name and
> leave `keys` empty.

---

## Option 2: Custom codec class (e.g. AWS KMS)

For external key management you supply a Python module implementing
`temporalio.converter.PayloadCodec`. Datafold loads it in the server and in
every Temporal worker, so all payloads are encoded/decoded through your codec.

### Step 1: Write the codec

Implement `encode` and `decode`. The class below is a skeleton — replace the
body with calls to your KMS:

```python
# temporal_codec.py
from temporalio.api.common.v1 import Payload
from temporalio.converter import PayloadCodec


class KMSCodec(PayloadCodec):
    async def encode(self, payloads: list[Payload]) -> list[Payload]:
        # Encrypt each payload's data with your KMS / external key here.
        ...

    async def decode(self, payloads: list[Payload]) -> list[Payload]:
        # Reverse of encode().
        ...
```

The file's module stem (`temporal_codec`) and the class name (`KMSCodec`) form
the `codecClass` value: `"temporal_codec:KMSCodec"`.

### Step 2: Package the codec as a ConfigMap

Create the ConfigMap in the Datafold namespace **before** deploying. The key in
the ConfigMap must match `fileName` and end in `.py`:

```bash
kubectl create configmap acme-temporal-codec \
  --from-file=temporal_codec.py=./temporal_codec.py \
  -n <YOUR_NAMESPACE>
```

The chart mounts this file into the server and every `worker-temporal` container
at `/datafold/plugins/<fileName>`. The loader resolves `codecClass` by looking up
`<module_stem>.py` in that fixed directory — no `PYTHONPATH` changes needed.

### Step 3: Reference it in your values / CR

`codecClass` takes precedence over the built-in AES-256-GCM codec, so you do not
also set `encryption.keys`.

#### Helm

```yaml
global:
  temporal:
    corsOrigins: "https://cloud.temporal.io"
    encryption:
      codecClass: "temporal_codec:KMSCodec"
      customCodec:
        configMapName: acme-temporal-codec
        fileName: temporal_codec.py
```

See [`examples/helm/acme-temporal-cloud-custom-codec.yaml`](../examples/helm/acme-temporal-cloud-custom-codec.yaml).

#### Operator

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

See [`examples/operator/acme-temporal-cloud-custom-codec.yaml`](../examples/operator/acme-temporal-cloud-custom-codec.yaml).

When the codec pod needs IAM permissions (e.g. to call KMS), attach them to the
server and worker service accounts via their `roleArn` (AWS) or service-account
annotations for your cloud.

---

## The codec server and `corsOrigins`

So the Temporal Cloud UI can display decoded payloads in the workflow history
view, Datafold runs a **codec server** endpoint. `global.temporal.corsOrigins`
sets `TEMPORAL_CODEC_CORS_ORIGINS` — a comma-separated allowlist of origins
permitted to call it (commonly `https://cloud.temporal.io`). It **must not** be
`*`. Leave it empty if you do not need decoded payloads in the Temporal Cloud UI.

---

## Environment variables (reference)

The encryption settings render into the following, consumed by the server and
all `worker-temporal` pods:

| Setting | Rendered as | Source field |
|---------|-------------|--------------|
| Active key id | `TEMPORAL_ENCRYPTION_ACTIVE_KEY_ID` | `encryption.activeKeyId` |
| Encryption keys | `TEMPORAL_ENCRYPTION_KEY_<n>` (Secret, `"<id>:<value>"`) | `encryption.keys` |
| Codec class | `TEMPORAL_CODEC_CLASS` | `encryption.codecClass` |
| Codec CORS allowlist | `TEMPORAL_CODEC_CORS_ORIGINS` | `corsOrigins` |
| Codec source file | mounted at `/datafold/plugins/<fileName>` | `encryption.customCodec` |

---

## Placeholder Reference

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `<YOUR_NAMESPACE>` | Kubernetes namespace for Datafold | `acme-datafold` |
| `<BASE64_AES256_KEY>` | Base64-encoded 32-byte AES key | `openssl rand -base64 32` |

---

## Next Step

Return to the deployment guide:

- [Deploy with the Operator (preferred)](deploy-operator.md)
- [Deploy with direct Helm values (alternative)](deploy-helm.md)
