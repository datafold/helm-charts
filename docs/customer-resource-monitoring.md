# Customer Resource Monitoring

This document describes how to configure Datafold's monitoring infrastructure to
forward observability data (metrics, logs, APM traces) to a customer's own
Datadog account, giving them visibility into the four golden signals for their
Datafold deployment: **latency**, **traffic**, **errors**, and **saturation**.

## Overview

Datafold ships with a Datadog agent that collects:

- **Infrastructure metrics** (CPU, memory, disk, network for all pods)
- **Application logs** (sent from the Datafold application via TCP socket)
- **DogStatsD custom metrics** (application-level business metrics)
- **APM traces** (when enabled)
- **Container and process metrics**
- **OOM kill events**

By default, all of this data is sent to Datafold's own Datadog account. With
customer monitoring enabled, the Datadog agent **dual-ships** the same data to
the customer's Datadog account, so they can build their own dashboards, set up
alerts, and receive notifications when resource thresholds are being approached.

The entire feature is self-contained in the `datadog` subchart. No changes are
required to the parent Datafold chart, the application code, or the CRD.

## Prerequisites

1. The customer must have a Datadog account
2. The customer must provide their **Datadog API key**
3. The customer should know their **Datadog site** (see table below)

### Datadog Sites

| Site Name | Site Value            |
|-----------|-----------------------|
| US1       | `datadoghq.com`       |
| US3       | `us3.datadoghq.com`   |
| US5       | `us5.datadoghq.com`   |
| EU1       | `datadoghq.eu`        |
| AP1       | `ap1.datadoghq.com`   |
| US1-FED   | `ddog-gov.com`        |

## Configuration

### Step 1: Provide the Customer's Datadog API Key

The customer's API key needs to be present in the shared Kubernetes secret under
the key `DATAFOLD_CUSTOMER_DD_API_KEY`. Use the existing `customSecrets`
mechanism:

```yaml
global:
  customSecrets:
    - name: DATAFOLD_CUSTOMER_DD_API_KEY
      value: "<customer-datadog-api-key>"
```

If the customer manages their own secrets (`global.manageSecretsYourself: true`),
add the key `DATAFOLD_CUSTOMER_DD_API_KEY` directly to their secret.

### Step 2: Enable Dual Shipping on the Datadog Subchart

Set the `customerMonitoring` values on the `datadog` subchart:

```yaml
datadog:
  customerMonitoring:
    enabled: true
    site: "datadoghq.com"   # Customer's Datadog site
    metrics: true            # Forward infrastructure + custom metrics
    logs: true               # Forward application + container logs
    apm: false               # Forward APM traces (requires apm enabled)
```

Each signal type can be independently toggled.

### Via DatafoldApplication CRD

Use `components.datadog.rawValues` and `secrets.customSecrets`:

```yaml
apiVersion: datafold.datafold.com/v1alpha1
kind: DatafoldApplication
spec:
  secrets:
    customSecrets:
      - name: DATAFOLD_CUSTOMER_DD_API_KEY
        value: "<customer-datadog-api-key>"
  components:
    datadog:
      rawValues:
        customerMonitoring:
          enabled: true
          site: "datadoghq.com"
          metrics: true
          logs: true
          apm: false
```

See `examples/datafold-application-customer-monitoring.yaml` for a full example.

## What Gets Forwarded

| Signal Type | Env Variable                            | Description                                      |
|-------------|-----------------------------------------|--------------------------------------------------|
| Metrics     | `DD_ADDITIONAL_ENDPOINTS`               | Infrastructure metrics, DogStatsD custom metrics  |
| Logs        | `DD_LOGS_CONFIG_ADDITIONAL_ENDPOINTS`   | Application logs, container logs                  |
| APM         | `DD_APM_ADDITIONAL_ENDPOINTS`           | Application traces (requires APM to be enabled)   |

### Four Golden Signals Visibility

With customer monitoring enabled, the customer can observe:

- **Latency**: Request duration metrics, APM trace spans
- **Traffic**: Request rate metrics, log volume
- **Errors**: Error rate metrics, error logs, exception traces
- **Saturation**: CPU/memory/disk utilization, OOM kill events, container resource metrics

## Recommended Customer Dashboards

Once data flows to the customer's Datadog account, they can create dashboards
and monitors for:

### Resource Utilization
- Pod CPU usage vs limits
- Pod memory usage vs limits (critical for OOM prevention)
- Disk usage on persistent volumes (ClickHouse, Redis)

### Application Health
- HTTP request latency (p50, p95, p99)
- Error rates by endpoint
- Worker queue depth and processing time
- Task success/failure rates

### Alerting Recommendations
- Memory usage > 80% of limit (early warning for OOM)
- CPU throttling detected
- Error rate spike (> 2x baseline)
- Worker queue backlog growing
- Disk usage > 85%

## Architecture

```
┌─────────────────┐     TCP :10518      ┌──────────────────┐
│  Datafold App   │────────────────────→│   Datadog Agent   │
│  (logs via      │                     │                   │
│   socket)       │     UDP :8125       │  Dual Shipping:   │
│                 │────────────────────→│                   │
│  (metrics via   │                     │  ┌─────────────┐  │
│   DogStatsD)    │     TCP :8126       │  │ Datafold DD │──┼──→ Datafold Datadog
│                 │────────────────────→│  │  (primary)  │  │
│  (traces via    │                     │  └─────────────┘  │
│   APM)          │                     │                   │
└─────────────────┘                     │  ┌─────────────┐  │
                                        │  │ Customer DD │──┼──→ Customer Datadog
                                        │  │ (secondary) │  │
                                        │  └─────────────┘  │
                                        └──────────────────┘
```

The Datadog agent handles the fan-out internally using its built-in dual
shipping capability. No additional infrastructure is required.

## Security Considerations

- The customer's API key is stored as a Kubernetes secret and injected as an
  environment variable into the Datadog agent pod
- Data is transmitted over HTTPS to the customer's Datadog site
- The customer receives the same data that Datafold receives; no filtering is
  applied. Sensitive data in logs should be handled by Datadog's sensitive data
  scanner on the customer's side
- The customer's API key only allows data ingestion, not querying Datafold's
  Datadog account

## Troubleshooting

### Verify dual shipping is active

Check the Datadog agent pod's environment variables:

```bash
kubectl exec -it <datadog-agent-pod> -- env | grep DD_ADDITIONAL
kubectl exec -it <datadog-agent-pod> -- env | grep DD_LOGS_CONFIG
```

### Check agent status

```bash
kubectl exec -it <datadog-agent-pod> -- agent status
```

Look for the "Additional Endpoints" section in the output.

### Common issues

1. **No data in customer's Datadog**: Verify the customer's API key is correct
   and the site matches their account
2. **Logs not appearing**: Ensure `DD_LOGS_CONFIG_USE_HTTP` is set to `true`
   (this is set automatically when customer log shipping is enabled)
3. **High agent memory**: Dual shipping doubles the agent's outbound data
   volume; consider increasing the agent's memory limits if needed
