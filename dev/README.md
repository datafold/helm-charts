# Development Configuration

This directory contains configuration files for local development of Datafold Helm charts.

## Configuration Files

### `config.yaml`
Main configuration file that overrides default values for development. Contains:
- Component-specific settings (server, scheduler, dfshell)
- Global application configuration
- Worker configurations for different queue types
- Resource limits and requests
- Component installation flags

### Infrastructure Configuration Files
The infrastructure configuration has been split into cloud provider-specific files:

- **`infra-aws.yaml`** - AWS-specific configuration with EKS and IAM roles
- **`infra-gcp.yaml`** - GCP-specific configuration with GKE and Workload Identity  
- **`infra-azure.yaml`** - Azure-specific configuration with AKS and Azure AD Workload Identity
- **`infra-local.yaml`** - Local development configuration
- **`infra.yaml`** - Reference file with usage instructions

Each file contains:
- Global infrastructure settings
- Service account configurations for all components
- Database connection settings
- Cloud provider configurations
- Datadog monitoring settings

### `secrets.yaml`
Secret values for development environment:
- Database credentials
- API keys and tokens
- Mail server configuration
- Encryption keys
- Operator settings

## Cloud Provider Configurations

### AWS Configuration (`infra-aws.yaml`)
AWS configuration includes:
- EKS service account configurations with IAM roles (IRSA)
- AWS EBS storage class (`gp3`)
- AWS Load Balancer target group configuration
- RDS/Aurora database connection examples
- ElastiCache Redis configuration examples

### GCP Configuration (`infra-gcp.yaml`)
GCP configuration includes:
- GKE service account configurations with Workload Identity
- Persistent Disk SSD storage class
- GCP Network Endpoint Groups
- Cloud SQL/Memorystore examples

### Azure Configuration (`infra-azure.yaml`)
Azure configuration includes:
- AKS service account configurations with Azure AD Workload Identity
- Managed Premium storage class
- Azure Database services examples

### Local Development Configuration (`infra-local.yaml`)
Local development configuration includes:
- Simplified service accounts (no cloud-specific annotations)
- Local storage class
- Development-optimized settings

## Usage

These files are used by the jeeves development tool to configure the Helm deployment:

```bash
# Set environment variables
export DATAFOLD_K8S_SECRETFILE="./dev/secrets.yaml"
export DATAFOLD_K8S_CONFIGFILE="./dev/config.yaml"
export DATAFOLD_DEPLOY_NAME="datafold-dev"
export TAG="latest"

# Choose your infrastructure configuration
export DATAFOLD_DEV_OVERRIDES="./dev/infra-aws.yaml"    # For AWS
# export DATAFOLD_DEV_OVERRIDES="./dev/infra-gcp.yaml"  # For GCP
# export DATAFOLD_DEV_OVERRIDES="./dev/infra-azure.yaml" # For Azure
# export DATAFOLD_DEV_OVERRIDES="./dev/infra-local.yaml" # For Local Development

# Install/update deployment
./jeeves/j dev install run
./jeeves/j dev update run

# Validate configuration
./jeeves/j dev kubeconform run --strict
```

## Configuration Structure

### Worker Types

The configuration supports multiple worker types for different workloads:

- **worker**: General purpose worker for celery, api, ci, interactive, freshpaint queues
- **worker-interactive**: Dedicated worker for interactive tasks
- **worker-catalog**: Worker for lineage and catalog operations
- **worker-singletons**: Worker for singleton tasks
- **worker-monitor**: Worker for alert processing
- **worker-temporal**: Worker for Temporal workflow processing
- **storage-worker**: Worker for local storage operations (disabled by default in dev)

### Resource Configuration

Each worker type can be configured with:
- `replicaCount`: Number of worker pods
- `terminationGracePeriodSeconds`: Grace period for pod termination
- `worker.queues`: Celery queues to process
- `worker.tasks`: Maximum tasks per worker
- `worker.memory`: Memory limit per worker (in KB)
- `worker.count`: Number of worker processes per pod
- `resources`: Kubernetes resource requests and limits

### Cloud-Specific Features

#### AWS Features
- **IAM Roles for Service Accounts (IRSA)**: Service accounts with AWS IAM role annotations
- **EBS Storage**: Uses `gp3` storage class for persistent volumes
- **Load Balancer Integration**: AWS Load Balancer Controller target group binding
- **RDS/Aurora**: Database connection examples for managed databases

#### GCP Features
- **Workload Identity**: Service accounts with GCP Workload Identity annotations
- **Persistent Disk**: Uses `pd-ssd` storage class
- **Network Endpoint Groups**: GCP NEG configuration for load balancing
- **Cloud SQL/Memorystore**: Database connection examples

#### Azure Features
- **Azure AD Workload Identity**: Service accounts with Azure AD annotations
- **Managed Disks**: Uses `managed-premium` storage class
- **Azure Database**: Database connection examples for Azure managed databases

### Development vs Production

Key differences for development:
- `enforceHttps: "false"` - Disabled for local development
- `storageOnPV: "false"` - Uses ephemeral storage
- Reduced resource limits
- Simplified authentication
- Disabled external services (Datadog, etc.)

## Customization

To customize for your development environment:

1. **Choose cloud provider**: Select the appropriate infrastructure file
2. **Update server name**: Change `global.serverName` in the selected configuration
3. **Adjust resources**: Modify resource limits in worker configurations
4. **Enable/disable components**: Set `install: true/false` for components
5. **Configure databases**: Update connection details in the selected configuration
6. **Set secrets**: Update values in `secrets.yaml`

## Cloud Provider Setup

### AWS Setup
1. Create IAM roles for each service account
2. Configure EKS cluster with OIDC provider
3. Set up AWS Load Balancer Controller
4. Create RDS/Aurora databases if using managed databases

### GCP Setup
1. Enable Workload Identity on GKE cluster
2. Create GCP service accounts
3. Configure IAM bindings
4. Set up Cloud SQL/Memorystore if using managed databases

### Azure Setup
1. Enable Azure AD Workload Identity on AKS cluster
2. Create Azure AD application registrations
3. Configure role assignments
4. Set up Azure Database services if using managed databases

## Troubleshooting

### Common Issues

1. **Resource constraints**: Reduce replica counts or resource limits if your cluster is small
2. **Storage issues**: Ensure your cluster supports the specified storage class
3. **Service account errors**: Check that service accounts are properly configured
4. **Database connection**: Verify database credentials and connectivity
5. **Cloud provider authentication**: Ensure proper IAM/Workload Identity setup

### Validation

Use kubeconform to validate your configuration:

```bash
./jeeves/j dev kubeconform run --strict
```

This will validate that your Helm charts render valid Kubernetes manifests.

## Security Notes

⚠️ **Important**: These configuration files contain development credentials and should not be used in production. The secrets and configurations are simplified for development purposes only.

For production deployments:
- Use proper secret management (HashiCorp Vault, AWS Secrets Manager, etc.)
- Implement proper RBAC and service accounts
- Use production-grade storage classes
- Enable security features like HTTPS enforcement
- Configure proper monitoring and logging
- Use cloud provider-specific security features (IAM, Workload Identity, etc.) 