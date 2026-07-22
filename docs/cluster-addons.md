# Cluster Add-ons: metrics-server, Cluster Autoscaler, AWS Load Balancer Controller, Datadog Operator

These are standard Kubernetes cluster components, not part of the Datafold
application itself. The cluster should have them installed and healthy before
(or alongside) the [prerequisites](prerequisites.md) — Datafold's Horizontal
Pod Autoscaling, node capacity, Service/Ingress-provisioned load balancers,
and monitoring all depend on them.

> **Support scope:** metrics-server, Cluster Autoscaler, the AWS Load Balancer
> Controller, and the Datadog Operator are third-party components. Datafold
> provides these instructions as guidance, but support is scoped to the
> Datafold application. For issues with these components themselves, refer to
> their upstream documentation (linked in each section below).

---

## Which of these do I need?

| Component | Cloud scope | Why Datafold needs it |
|-----------|-------------|------------------------|
| [metrics-server](#metrics-server) | Any Kubernetes distribution | Powers `kubectl top` and any CPU/memory-based HPA on Datafold components |
| [Cluster Autoscaler](#cluster-autoscaler) | AWS (EKS) | Adds/removes nodes as Datafold and Temporal workloads scale. GKE and AKS have native node-pool autoscaling instead — see [note](#gcp--azure-note) |
| [AWS Load Balancer Controller](#aws-load-balancer-controller) | AWS (EKS) | Provisions ALB/NLB resources from `Ingress`/`Service` objects (e.g. the Datafold UI ingress). GKE and AKS provision load balancers natively — see [note](#gcp--azure-note) |
| [Datadog Operator](#datadog-operator) | Any Kubernetes distribution | Only needed if this deployment monitors with Datadog (`monitoring.type: datadog`). Installs the operator only — the `DatadogAgent` CR is applied later, automatically, by the Datafold chart |

### GCP / Azure note

- **GKE**: node-pool autoscaling is enabled per pool (`--enable-autoscaling`
  on `gcloud container node-pools create`) — no separate chart to install.
  Ingress is provisioned natively via GKE's `gce`/`gce-internal` Ingress
  classes.
- **AKS**: the cluster autoscaler ships as an AKS add-on, enabled per node
  pool (`az aks nodepool update --enable-cluster-autoscaler`). Load balancers
  are provisioned via the built-in Azure cloud provider or Application
  Gateway Ingress Controller (AGIC).

metrics-server is still required on GKE and AKS the same way as EKS — see
below.

---

## metrics-server

[metrics-server](https://github.com/kubernetes-sigs/metrics-server) collects
resource usage (CPU/memory) from kubelets and exposes it via the
`metrics.k8s.io` API. Required for `kubectl top nodes`/`kubectl top pods` and
for any `HorizontalPodAutoscaler` that scales on CPU/memory.

### Install

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server
helm repo update

helm install metrics-server metrics-server/metrics-server \
  --namespace kube-system
```

No cloud-specific values are required — the chart's defaults work on EKS,
GKE, and AKS alike.

### Verify

```bash
kubectl rollout status deploy/metrics-server -n kube-system
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
```

Expected: the `v1beta1.metrics.k8s.io` APIService reports `AVAILABLE: True`,
and `kubectl top nodes` returns CPU/memory figures instead of an error.

---

## Cluster Autoscaler

[Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)
adjusts the number of nodes in an EKS managed node group's Auto Scaling Group
based on pending/unschedulable pods.

> **AWS shortcut:** If this cluster is provisioned with Datafold's
> [`terraform-aws-datafold`](https://github.com/datafold/terraform-aws-datafold)
> module, the IAM role and the required Auto Scaling Group discovery tags
> (`k8s.io/cluster-autoscaler/enabled`, `k8s.io/cluster-autoscaler/<CLUSTER_NAME>`)
> are already created for you — see the `cluster_autoscaler_role` module block
> in [`modules/eks/roles.tf`](https://github.com/datafold/terraform-aws-datafold/blob/main/modules/eks/roles.tf).
> Confirm the role exists (`<DEPLOYMENT_NAME>-cluster-autoscaler`), then skip
> straight to [Install](#install-1) — no manual IAM setup is needed.

### IAM / Workload Identity (EKS)

If you are **not** using the `terraform-aws-datafold` module, create an IAM
role with an OIDC trust policy scoped to
`system:serviceaccount:kube-system:cluster-auto-scaler`, granting the standard
[Cluster Autoscaler IAM policy](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md#iam-policy)
(`autoscaling:DescribeAutoScalingGroups`, `autoscaling:SetDesiredCapacity`,
`autoscaling:TerminateInstanceInAutoScalingGroup`,
`ec2:DescribeInstanceTypes`, etc., scoped by the
`k8s.io/cluster-autoscaler/<CLUSTER_NAME>` tag). Tag the node group's Auto
Scaling Group with:

- `k8s.io/cluster-autoscaler/enabled: true`
- `k8s.io/cluster-autoscaler/<CLUSTER_NAME>: owned`

### Install

```bash
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update

helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --version 9.35.0 \
  --set awsRegion=<AWS_REGION> \
  --set rbac.create=true \
  --set rbac.serviceAccount.name=cluster-auto-scaler \
  --set rbac.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::<ACCOUNT_ID>:role/<DEPLOYMENT_NAME>-cluster-autoscaler \
  --set autoDiscovery.clusterName=<CLUSTER_NAME> \
  --set autoDiscovery.enabled=true
```

### Verify

```bash
kubectl rollout status deploy/cluster-autoscaler-aws-cluster-autoscaler -n kube-system
kubectl logs -n kube-system -l "app.kubernetes.io/name=aws-cluster-autoscaler,app.kubernetes.io/instance=cluster-autoscaler" --tail=20
```

Expected: the deployment reports `1/1` ready, and logs show informer caches
populating (`Caches populated for *v1.Node ...`) with no IRSA/auth errors. If
the pod logs `AccessDenied` or similar, double-check the service account
annotation matches the IAM role's trust policy subject exactly
(`system:serviceaccount:kube-system:cluster-auto-scaler`).

---

## AWS Load Balancer Controller

The [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
watches `Ingress` and `Service` (type `LoadBalancer`) objects and provisions
matching ALB/NLB resources. Datafold's UI ingress and any `LoadBalancer`-type
Services depend on this controller running.

> **AWS shortcut:** If this cluster is provisioned with Datafold's
> [`terraform-aws-datafold`](https://github.com/datafold/terraform-aws-datafold)
> module, the IAM role and policy (`AWSLoadBalancerControllerIAMPolicy`
> equivalent) already exist — see the `k8s_load_balancer_controller_role`
> module block in
> [`modules/eks/roles.tf`](https://github.com/datafold/terraform-aws-datafold/blob/main/modules/eks/roles.tf).
> Confirm the role exists (`<DEPLOYMENT_NAME>-lb-controller`), then skip
> straight to [creating the service account](#create-the-service-account) —
> do **not** also run `eksctl create iamserviceaccount` or
> `aws iam create-policy` below, that would create a second, untracked IAM
> role/policy alongside the Terraform-managed one.

### IAM / Workload Identity (EKS) — only if not using the Terraform module

Full instructions:
[AWS docs — Install AWS Load Balancer Controller with Helm](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html).
Summary:

```bash
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

eksctl create iamserviceaccount \
  --cluster=<CLUSTER_NAME> \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --region <AWS_REGION> \
  --approve
```

### Create the service account

If you used the **Terraform shortcut** above, `eksctl` did not create the
service account for you — create it directly, pointing at the
Terraform-managed role:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
    app.kubernetes.io/component: controller
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/<DEPLOYMENT_NAME>-lb-controller
    eks.amazonaws.com/sts-regional-endpoints: "true"
```

```bash
kubectl apply -f aws-load-balancer-controller-sa.yaml
```

### Install

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=<CLUSTER_NAME> \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --version 1.14.0
```

`serviceAccount.create=false` is required in both paths (Terraform shortcut
or manual `eksctl`) — the service account must already exist with the IRSA
annotation before the chart installs, otherwise Helm creates a second,
un-annotated one.

### Verify

```bash
kubectl rollout status deploy/aws-load-balancer-controller -n kube-system
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl logs -n kube-system deploy/aws-load-balancer-controller --tail=30
```

Expected: `2/2` ready, leader election acquired
(`successfully acquired lease kube-system/aws-load-balancer-controller-leader`),
and controllers for `ingress`, `service`, and `targetGroupBinding` all
starting cleanly with no auth errors.

The deployed chart does not receive security updates automatically — check
the [release page](https://github.com/aws/eks-charts/releases) periodically
and re-run `helm upgrade` with a newer `--version` when needed.

---

## Datadog Operator

The [Datadog Operator](https://docs.datadoghq.com/containers/kubernetes/installation/?tab=operator)
watches for `DatadogAgent` custom resources and reconciles the node
Agent/Cluster Agent DaemonSet+Deployment from them. Only install this if the
deployment monitors with Datadog (`DatafoldApplication.spec.monitoring.type:
datadog`).

> **This step only installs the operator itself.** Unlike the other add-ons on
> this page, you do **not** hand-write a `DatadogAgent` CR here. The Datafold
> chart ships its own `datadog` subchart
> (`charts/datafold/charts/datadog/templates/datadog_operator.yaml`) that
> renders the `DatadogAgent` CR automatically from
> `DatafoldApplication.spec.monitoring.datadog.*` (APM, NPM, log collection,
> `monitorPostgres`, `monitorKeda`, `monitorTemporal`, etc.) once the Datafold
> application is deployed — see [Deploy with Operator](deploy-operator.md).
> There is nothing to apply manually at this stage beyond the operator and the
> API/App key secret below.

### Install

```bash
helm repo add datadog https://helm.datadoghq.com
helm repo update
```

Datadog's own quickstart installs into the default namespace with a
standalone `datadog-secret` — for Datafold deployments, install the operator
into the **same namespace as the Datafold deployment** instead, since the
`DatadogAgent` CR created later by the `datadog` subchart lives there too:

```bash
helm install datadog-operator datadog/datadog-operator \
  --namespace <DATAFOLD_NAMESPACE>
```

### API / App key secret

The `DatadogAgent` CR the `datadog` subchart renders later reads its
credentials from `DATAFOLD_DD_API_KEY` / `DATAFOLD_DD_APP_KEY` keys on the
Datafold application's own secret (the same Secret referenced by
`DatafoldApplication.spec.monitoring.monitoringApiKey`), not a separate
`datadog-secret`. Populate those keys before enabling the `datadog` component
— see [Deploy with Operator](deploy-operator.md) for how application secrets
are provisioned.

### Verify

```bash
kubectl rollout status deploy/datadog-operator -n <DATAFOLD_NAMESPACE>
```

Expected: `1/1` ready. At this point there is intentionally **no**
`DatadogAgent` object yet:

```bash
kubectl get datadogagent -n <DATAFOLD_NAMESPACE>
```

The `DatadogAgent` (and the resulting node Agent DaemonSet + Cluster Agent
Deployment) appears only after the Datafold application is deployed with
`monitoring.type: datadog` — see
[Deploy with Operator](deploy-operator.md). If it doesn't appear, check the
Datadog Operator's own logs first:

```bash
kubectl logs -n <DATAFOLD_NAMESPACE> deploy/datadog-operator --tail=50
```

For the full set of configurable `DatadogAgent` fields (beyond what the
`datadog` subchart already exposes), see the
[Datadog Operator configuration reference](https://github.com/DataDog/datadog-operator/blob/main/docs/configuration.v2alpha1.md).
Some features (e.g. multi-line log aggregation) are configured via pod
annotations instead — see the
[advanced log collection docs](https://docs.datadoghq.com/agent/logs/advanced_log_collection/?tab=kubernetes#multi-line-aggregation).

---

## Placeholder Reference

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `<DEPLOYMENT_NAME>` | Your Datafold deployment name | `acme`, `production` |
| `<CLUSTER_NAME>` | EKS cluster name | `acme-datafold` |
| `<ACCOUNT_ID>` | AWS account ID | `123456789012` |
| `<AWS_REGION>` | AWS region | `us-east-2` |
| `<DATAFOLD_NAMESPACE>` | Kubernetes namespace the Datafold deployment runs in | `acme-datafold` |

---

## Next Step

Continue with the [Prerequisites overview](prerequisites.md) for PostgreSQL,
Temporal, and KEDA, then [deploy the Datafold application](deploy-operator.md).
