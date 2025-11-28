# Getting started

Official helm charts for deploying Datafold into Kubernetes.

## Preferred Method: Deploy with Datafold Operator

The recommended way to deploy Datafold is using our operator, which provides a simpler and more manageable deployment experience.

### Prerequisites

You'll need two files from Datafold:
- `datafold-operator-secrets.yaml` - Contains application secrets and configuration
- `datafold-docker-secret.yaml` - Contains Docker registry credentials

### Step 1: Create Namespace

Create a namespace for your Datafold deployment:

```shell
kubectl create namespace datafold-apps
kubectl config set-context --current --namespace=datafold-apps
```

### Step 2: Deploy Docker Secrets

Deploy the Docker registry secret to allow pulling private Datafold images:

```shell
kubectl apply -f datafold-docker-secret.yaml
```

### Step 3: Configure and Deploy Application Secrets

Update the `datafold-operator-secrets.yaml` file with your specific configuration (namespace, keys,
email server password, etc.) and deploy it:

```shell
kubectl apply -f datafold-operator-secrets.yaml
```

### Step 4: Add Helm Repository

Add the Datafold Helm repository:

```shell
helm repo add datafold https://charts.datafold.com
helm repo update
```

### Step 5: Deploy the Operator

Deploy the Datafold operator using the datafold-manager chart:

```shell
helm upgrade --install datafold-manager datafold/datafold-manager \
  --namespace datafold-apps \
  --set namespace.name=datafold-apps
```

### Step 6: Create DatafoldApplication

Create a `DatafoldApplication` custom resource to define your Datafold deployment. See the `examples/` directory for configuration templates:

```shell
kubectl apply -f examples/datafold-application-full.yaml
```

The operator will automatically deploy and manage your Datafold application based on the `DatafoldApplication` specification.

### Configuration Examples

The `examples/` directory contains various `DatafoldApplication` configuration templates for different deployment scenarios:

- `datafold-application-full.yaml` - Complete production configuration with all components
- `datafold-application-minimal.yaml` - Minimal configuration for development/testing
- `datafold-application-aws-lb.yaml` - AWS-specific configuration with load balancer
- `datafold-application-gcp-lb.yaml` - GCP-specific configuration with load balancer
- `datafold-application-signoz.yaml` - Configuration with SigNoz monitoring
- `datafold-application-datadog.yaml` - Configuration with Datadog monitoring

Choose the example that best matches your environment and customize it as needed.

### Getting the Latest Application Version

To fetch the most recent version of the Datafold application from the portal, you can use the following curl command:

```bash
curl -L https://portal.datafold.com/operator/v1/config \
     --header "Content-Type: application/json" \
     --header "Authorization: Bearer YOUR_API_KEY" \
     | jq -r '.version'
```

Replace `YOUR_API_KEY` with your actual API key from the `datafold-operator-secrets.yaml` file. The command will return the latest version string that you can use in your `DatafoldApplication` configuration.

**Note**: If you're using a custom portal URL (different from `https://portal.datafold.com`), replace the URL in the command accordingly.

## Alternative Method: Direct Helm Charts Deployment

For users who prefer the traditional Helm charts approach or need more direct control over the deployment.
This method is significantly harder and more complex.

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

### Create a values.yaml file

The helm chart requires a complete `values.yaml` file that merges configuration from multiple sources. You can use our example as a starting point:

```shell
# Copy and customize the example values file
cp examples/old-method-values-example.yaml values.yaml

# Edit values.yaml with your specific configuration:
# - Update serverName, clusterName, and other global settings
# - Configure your database connection details
# - Set up AWS load balancer ARNs and target groups
# - Adjust resource limits and worker counts as needed
```

The example file is based on a real dedicated cloud deployment and includes all necessary configuration sections.

### Install from our helm repo

Make sure to use the latest release from the helm-charts from our release list:

https://github.com/datafold/helm-charts/releases

```shell
helm repo add datafold https://charts.datafold.com
helm repo update
helm upgrade --install datafold datafold/datafold \
  --values values.yaml

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

### Local dev install

helm upgrade --install datafold-operator charts/datafold-operator \
  --namespace datafold-apps \
  --set namespace.name=datafold-apps
