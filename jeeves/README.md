# Jeeves - Helm Charts Development Tool

Jeeves is a development tool for managing Datafold Helm charts deployment and validation.

## Installation

1. Install Python dependencies:
```bash
pip install -r jeeves/requirements.txt
pip install typer-cli  # Optional: for better CLI experience
```

2. Install kubeconform (required for validation):
```bash
# On macOS:
brew install yannh/kubeconform/kubeconform

# On Linux:
wget https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz
tar -xzf kubeconform-linux-amd64.tar.gz
sudo mv kubeconform /usr/local/bin/
```

## Environment Variables

Set the following environment variables before using jeeves:

```bash
export DATAFOLD_K8S_SECRETFILE="./dev/secrets.yaml"
export DATAFOLD_K8S_CONFIGFILE="./dev/config.yaml"
export DATAFOLD_DEPLOY_NAME="datafold-test"
export DATAFOLD_DEV_OVERRIDES="./dev/infra.yaml"
export TAG="latest"
```

## Available Commands

### Development Commands

- `./j dev install run` - Install all helm charts
- `./j dev update run` - Update the deployment
- `./j dev uninstall run` - Uninstall the deployment
- `./j dev delete run` - Delete the deployment
- `./j dev render run` - Render all charts to console output
- `./j dev kubeconform run` - Validate charts against Kubernetes API schema



### Kubeconform Validation

The `kubeconform` command validates your Helm charts against the Kubernetes API schema:

```bash
# Basic validation (uses DATAFOLD_DEV_OVERRIDES environment variable)
./j dev kubeconform run

# Validate against specific Kubernetes version
./j dev kubeconform run --kubernetes-version "1.29.0"

# Enable strict validation
./j dev kubeconform run --strict

# Skip certain resource types
./j dev kubeconform run --skip-list "CustomResourceDefinition,ValidatingWebhookConfiguration"

# Output in JSON format
./j dev kubeconform run --output-format "json"

# Validate with specific cloud provider configuration
./j dev kubeconform run --cloud-provider aws
./j dev kubeconform run --cloud-provider gcp
./j dev kubeconform run --cloud-provider azure
```

### Cloud Provider Validation

You can validate your charts against different cloud provider configurations using the `--cloud-provider` parameter:

```bash
# AWS Configuration (automatically sets environment variables and infra file)
./j dev kubeconform run --cloud-provider aws --strict

# GCP Configuration (automatically sets environment variables and infra file)
./j dev kubeconform run --cloud-provider gcp --strict

# Azure Configuration (automatically sets environment variables and infra file)
./j dev kubeconform run --cloud-provider azure --strict
```

The `--cloud-provider` parameter automatically:
- Sets default environment variables if not already set
- Uses the appropriate infrastructure configuration file (`./dev/infra-{provider}.yaml`)
- Provides visual feedback with cloud provider emojis

You can also customize the validation parameters:

```bash
# Custom Kubernetes version and output format
./j dev kubeconform run --cloud-provider aws --kubernetes-version "1.29.0" --output-format "json"

# Skip certain resource types
./j dev kubeconform run --cloud-provider gcp --skip-list "CustomResourceDefinition,ValidatingWebhookConfiguration"

# Disable strict mode
./j dev kubeconform run --cloud-provider azure --strict false
```

For manual configuration, you can still use environment variables:

```bash
# Manual environment variable setup
export DATAFOLD_DEV_OVERRIDES="./dev/infra-aws.yaml"
./j dev kubeconform run --strict
```

### Upgrade Commands

- `./j upgrade version run --tag <version>` - Upgrade to a specific version

## GitHub Actions Integration

The repository includes GitHub Actions workflows that automatically run:

1. **Lint and Test Charts** (`.github/workflows/lint.yaml`) - Runs chart-testing linting
2. **Kubeconform Validation** (`.github/workflows/kubeconform.yaml`) - Validates charts against Kubernetes API schema
3. **Jeeves Pre-commit Checks** (`.github/workflows/jeeves-check.yaml`) - Runs pre-commit hooks

## Troubleshooting

### Kubeconform Installation Issues

If you encounter issues installing kubeconform:

1. Check if the binary is executable: `chmod +x /usr/local/bin/kubeconform`
2. Verify installation: `kubeconform -v`
3. For ARM64 systems, download the appropriate binary from the [releases page](https://github.com/yannh/kubeconform/releases)

### Environment Variable Issues

Make sure all required environment variables are set:
```bash
echo $DATAFOLD_K8S_SECRETFILE
echo $DATAFOLD_K8S_CONFIGFILE
echo $DATAFOLD_DEPLOY_NAME
echo $DATAFOLD_DEV_OVERRIDES
echo $TAG
```

### Validation Failures

If kubeconform validation fails:

1. Check the specific error messages in the output
2. Verify that your Kubernetes manifests use valid API versions
3. Consider using `--skip-list` to skip problematic resource types during development
4. Update to a newer Kubernetes version if using deprecated APIs
