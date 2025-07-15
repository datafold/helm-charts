import enum
import os
import sh
import tempfile
import subprocess
from typer import Typer


DEFAULT_NAMESPACE = "datafold"


class EnvVar(enum.StrEnum):
    DATAFOLD_K8S_SECRETFILE = "DATAFOLD_K8S_SECRETFILE"
    DATAFOLD_K8S_CONFIGFILE = "DATAFOLD_K8S_CONFIGFILE"
    DATAFOLD_DEPLOY_NAME = "DATAFOLD_DEPLOY_NAME"
    DATAFOLD_DEV_OVERRIDES = "DATAFOLD_DEV_OVERRIDES"
    TAG = "TAG"


class CloudProvider(enum.StrEnum):
    AWS = "aws"
    GCP = "gcp"
    AZURE = "azure"


dev = Typer(no_args_is_help=True, help='Commands useful for local development environment.')


def _check_env_var(name: str):
    val = os.getenv(name)
    if not val:
        raise Exception(f"Env var {name} is not present, but is required.")


def _check_env_vars_present():
    for name in EnvVar:
        _check_env_var(name)


def _set_correct_namespace():
    sh.kubectl.config("set-context", "--current", f"--namespace={DEFAULT_NAMESPACE}")


def _check_environment():
    _check_env_vars_present()
    _set_correct_namespace()


def _common_args():
    return [
        os.getenv(EnvVar.DATAFOLD_DEPLOY_NAME),
        './charts/datafold',
        '-f',
        os.getenv(EnvVar.DATAFOLD_K8S_SECRETFILE),
        '-f',
        os.getenv(EnvVar.DATAFOLD_K8S_CONFIGFILE),
        '-f',
        os.getenv(EnvVar.DATAFOLD_DEV_OVERRIDES),
        '--set',
        f'global.datafoldVersion={os.getenv(EnvVar.TAG)}',
    ]


def _set_default_env_vars():
    """Set default environment variables if not already set."""
    defaults = {
        'DATAFOLD_K8S_SECRETFILE': "./dev/secrets.yaml",
        'DATAFOLD_K8S_CONFIGFILE': "./dev/config.yaml",
        'DATAFOLD_DEPLOY_NAME': "datafold-test",
        'TAG': "latest",
    }

    for var, default_value in defaults.items():
        if not os.getenv(var):
            os.environ[var] = default_value
            print(f"Set {var}={default_value}")


def _get_infra_file_path(provider: CloudProvider) -> str:
    """Get the infrastructure file path for the given cloud provider."""
    return f"./dev/infra-{provider.value}.yaml"


@dev.command()
def install():
    """Installs all helm charts."""
    _check_environment()

    args = ['--install']
    args.extend(_common_args())

    out = sh.helm.upgrade(args, _fg=True)
    print(out)


@dev.command()
def update():
    """Updates the deployment."""
    _check_environment()
    out = sh.helm.upgrade(_common_args(), _fg=True)
    print(out)


@dev.command()
def uninstall():
    """Uninstalls the deployment."""
    _check_environment()
    out = sh.helm.uninstall(os.getenv(EnvVar.DATAFOLD_DEPLOY_NAME), _fg=True)
    print(out)


@dev.command()
def delete():
    """Deletes the deployment."""
    _check_environment()
    out = sh.helm.delete(os.getenv(EnvVar.DATAFOLD_DEPLOY_NAME), _fg=True)
    print(out)


@dev.command()
def render():
    """Renders all charts to console output for validation."""
    _check_environment()
    args = ['--debug']
    args.extend(_common_args())
    out = sh.helm.template(args, _fg=True)
    print(out)


@dev.command()
def kubeconform(
    cloud_provider: CloudProvider,
    kubernetes_version: str = "1.30.0",
    strict: bool = True,
    skip_list: str = "",
    output_format: str = "text",
    secrets_file: str = "./dev/secrets.yaml",
    config_file: str = "./dev/config.yaml",
    deploy_name: str = "datafold-test",
    tag: str = "latest",
):
    """
    Validates rendered Helm charts against Kubernetes API schema using kubeconform.

    Args:
        kubernetes_version: Kubernetes version to validate against (default: 1.30.0)
        strict: Enable strict validation (default: False)
        skip_list: Comma-separated list of resources to skip validation
        output_format: Output format (text, json, junit, tap) (default: text)
        cloud_provider: Cloud provider to use for infrastructure configuration (aws, gcp, azure)
    """
    # Check if kubeconform is installed
    try:
        subprocess.run(["kubeconform", "-h"], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Error: kubeconform is not installed. Please install it first:")
        print("  # On macOS:")
        print("  brew install yannh/kubeconform/kubeconform")
        print("  # On Linux:")
        print(
            "  wget https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz"
        )
        print("  tar -xzf kubeconform-linux-amd64.tar.gz")
        print("  sudo mv kubeconform /usr/local/bin/")
        return

    # Handle cloud provider configuration
    infra_file = _get_infra_file_path(cloud_provider)

    # Set cloud provider emoji for output
    provider_emoji = {CloudProvider.AWS: "🌩️", CloudProvider.GCP: "☁️", CloudProvider.AZURE: "🔷"}
    print(
        f"{provider_emoji[cloud_provider]} Running kubeconform validation for "
        f"{cloud_provider.value.upper()}..."
    )
    print(f"Using infrastructure file: {infra_file}")

    # Render Helm templates to temporary file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as temp_file:
        try:
            # Build helm template command with all YAML files
            helm_args = [
                deploy_name,
                './charts/datafold',
                '-f',
                secrets_file,
                '-f',
                config_file,
                '-f',
                infra_file,
                '--set',
                f'global.datafoldVersion={tag}',
                '--debug',
            ]

            print(f"Running helm template with args: {' '.join(helm_args)}")
            print("-" * 50)

            # Capture helm template output
            sh.helm.template(helm_args, _out=temp_file.name)

            # Build kubeconform command
            kubeconform_cmd = [
                "kubeconform",
                "-kubernetes-version",
                kubernetes_version,
                "-output",
                output_format,
            ]

            if strict:
                kubeconform_cmd.append("-strict")

            # Add default skip list for custom resources that aren't in standard Kubernetes API
            default_skip_list = "TargetGroupBinding,DatadogAgent,DfAppManager"
            if skip_list:
                final_skip_list = f"{skip_list},{default_skip_list}"
            else:
                final_skip_list = default_skip_list

            kubeconform_cmd.extend(["-skip", final_skip_list])
            kubeconform_cmd.append(temp_file.name)

            # Run kubeconform
            print(f"Running kubeconform validation against Kubernetes {kubernetes_version}...")
            print(f"Skipping custom resources: {final_skip_list}")
            print(f"Command: {' '.join(kubeconform_cmd)}")
            print("-" * 50)

            subprocess.run(kubeconform_cmd, check=True)
            print("-" * 50)
            print("✅ kubeconform validation passed!")

        except subprocess.CalledProcessError as e:
            print(f"❌ kubeconform validation failed with exit code {e.returncode}")
            raise
        finally:
            # Do not delete the temp file so it can be inspected
            print(f"Rendered Helm output is available at: {temp_file.name}")
