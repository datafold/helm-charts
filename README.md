# Getting started

Official helm charts for deploying datafold into k8s.

This repository is in development and the instructions for installation and
upgrades will be added later.

### Prepare your shell environment

We will run a couple of commands where we want the kubernetes operations to execute
in the same namespace. We will set that namespace name in a shell environment variable,
so we use the same value consistently.

You can change `datafold` into any other namespace name you like.

```shell
kubectl create namespace datafold
kubectl config set-context --current --namespace=datafold
```

### Receive a json key to pull images

Our images are stored on a private registry. You can request a JSON key to be used
to pull those images. Install that json key as follows, paying attention to the
values of docker-server and you have the correct namespace targeted in your context.

```
kubectl create secret docker-registry datafold-docker-secret \
  --docker-server=us-docker.pkg.dev \
  --docker-username=_json_key \
  --docker-password="$(cat ~/json-key-file.json)" \
  --docker-email=support@datafold.com
```

### Install from our helm repo

Make sure to use the latest release from the helm-charts from our release list:

https://github.com/datafold/helm-charts/releases

(replace 0.6.84 with the most recent release number)

```
helm repo add datafold https://charts.datafold.com
helm upgrade --install datafold datafold/datafold \
  --version 0.6.84 \
  --set global.datafoldVersion="<version_tag>" \
  --set global.serverName="<access-url-on-lb>" \
  --set global.cloudProvider="aws" \
  --set global.awsTargetGroupArn="<replace-with-target-group-arn>" \
  --set global.awsLbCtrlArn="<replace-with-load-balancer-controller-role-arn>"

## Development and Validation

### Kubeconform Validation

This repository includes kubeconform validation to ensure Helm charts conform to the Kubernetes API schema. You can run validation locally using the jeeves tool:

```bash
# Install dependencies
pip install -r jeeves/requirements.txt

# Set environment variables (optional - wrapper commands set these automatically)
export DATAFOLD_K8S_SECRETFILE="./dev/secrets.yaml"
export DATAFOLD_K8S_CONFIGFILE="./dev/config.yaml"
export DATAFOLD_DEPLOY_NAME="datafold-test"
export TAG="latest"

# Run kubeconform validation for different cloud providers
# AWS Configuration (automatically sets environment variables and infra file)
./j dev kubeconform run --cloud-provider aws --strict

# GCP Configuration (automatically sets environment variables and infra file)
./j dev kubeconform run --cloud-provider gcp --strict

# Azure Configuration (automatically sets environment variables and infra file)
./j dev kubeconform run --cloud-provider azure --strict

# Custom validation parameters
./j dev kubeconform run --cloud-provider aws --kubernetes-version "1.29.0" --output-format "json"
./j dev kubeconform run --cloud-provider gcp --skip-list "CustomResourceDefinition,ValidatingWebhookConfiguration"
./j dev kubeconform run --cloud-provider azure --strict false
```

The validation runs automatically on pull requests for all three cloud providers (AWS, GCP, Azure) to ensure your charts work correctly across different Kubernetes environments.

For more information about jeeves and available commands, see [jeeves/README.md](jeeves/README.md).
```