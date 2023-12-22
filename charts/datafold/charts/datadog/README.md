# Install datadog

Installing datadog requires some other resources to be present on the cluster.
Here are the installation instructions for k8s:

https://docs.datadoghq.com/containers/kubernetes/installation/?tab=operator

```shell
> helm repo add datadog https://helm.datadoghq.com
> helm install my-datadog-operator datadog/datadog-operator
> kubectl create secret generic datadog-secret --from-literal api-key=<DATADOG_API_KEY>
```

After that, you can enable the install flag for datadog and
apply these charts.

Verify this page if you need to apply additional settings:

https://github.com/DataDog/datadog-operator/blob/main/docs/configuration.v2alpha1.md

Some features are set through annotations:

https://docs.datadoghq.com/agent/logs/advanced_log_collection/?tab=kubernetes#multi-line-aggregation
