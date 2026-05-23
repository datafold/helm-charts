# Temporal Cloud Payload Encryption

Datafold supports two approaches for encrypting Temporal workflow payloads when using Temporal Cloud:

1. **Built-in AES-256-GCM codec** — provide one or more base64-encoded keys via `global.temporal.encryption.keys`. No additional setup needed.
2. **Custom codec class** — supply a Python file that implements the `temporalio.converter.PayloadCodec` interface. Use this when you need external key management (e.g. AWS KMS).

---

## Built-In AES-256-GCM Codec

No custom file needed. Set keys in your CR or values:

```yaml
global:
  temporal:
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

Generate a key with:

```bash
openssl rand -base64 32
```

Store it in a Kubernetes Secret:

```bash
kubectl create secret generic datafold-operator-secrets \
  --from-literal=temporalEncryptionKeyV1="$(openssl rand -base64 32)" \
  -n <YOUR_NAMESPACE>
```

---

## Custom Codec Class (e.g. AWS KMS)

### 1. Write the codec

Create a Python file (e.g. `temporal_codec.py`) that implements the `temporalio.converter.PayloadCodec` interface:

```python
from temporalio.converter import PayloadCodec
from temporalio.api.common.v1 import Payload
from typing import Iterable

class KMSCodec(PayloadCodec):
    async def encode(self, payloads: Iterable[Payload]) -> list[Payload]:
        # Encrypt each payload using your key provider (e.g. AWS KMS)
        ...

    async def decode(self, payloads: Iterable[Payload]) -> list[Payload]:
        # Decrypt each payload using your key provider
        ...
```

The module stem (`temporal_codec`) and class name (`KMSCodec`) must match the `codecClass` value in your configuration: `"temporal_codec:KMSCodec"`.

### 2. Create the ConfigMap

```bash
kubectl create configmap acme-temporal-codec \
  --from-file=temporal_codec.py=./temporal_codec.py \
  -n <YOUR_NAMESPACE>
```

### 3. Reference the ConfigMap in your CR or values

**Operator (DatafoldApplication CR):**

```yaml
spec:
  global:
    temporal:
      encryption:
        codecClass: "temporal_codec:KMSCodec"
        customCodec:
          configMapName: acme-temporal-codec
          fileName: temporal_codec.py
```

**Direct Helm values:**

```yaml
global:
  temporal:
    encryption:
      codecClass: "temporal_codec:KMSCodec"
      customCodec:
        configMapName: acme-temporal-codec
        fileName: temporal_codec.py
```

The operator mounts the file from the ConfigMap into all Temporal containers at `/datafold/plugins/<fileName>`. The `TEMPORAL_CODEC_CLASS` environment variable is set automatically from `codecClass`.

See the [full example CR](../examples/operator/acme-temporal-cloud-custom-codec.yaml) for a complete working configuration.
