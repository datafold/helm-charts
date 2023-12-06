import enum
import os
import sh
from typer import Typer


class EnvVar(enum.StrEnum):
    DATAFOLD_K8S_SECRETFILE = "DATAFOLD_K8S_SECRETFILE"
    DATAFOLD_K8S_CONFIGFILE = "DATAFOLD_K8S_CONFIGFILE"
    DATAFOLD_DEPLOY_NAME = "DATAFOLD_DEPLOY_NAME"
    DATAFOLD_DEV_OVERRIDES = "DATAFOLD_DEV_OVERRIDES"
    TAG = "TAG"


dev = Typer(
    no_args_is_help=True, help='Commands useful for local development environment.'
)


def _check_env_var(name: str):
    val = os.getenv(name)
    if not val:
        raise Exception(f"Env var {name} is not present, but is required.")


def _check_env_vars_present():
    for name in EnvVar:
        _check_env_var(name)


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


@dev.command()
def install():
    """Installs all helm charts."""
    _check_env_vars_present()

    args = ['--install']
    args.extend(_common_args())

    out = sh.helm.upgrade(args, _fg=True)
    print(out)


@dev.command()
def update():
    """Updates the deployment."""
    _check_env_vars_present()
    out = sh.helm.upgrade(_common_args(), _fg=True)
    print(out)


@dev.command()
def uninstall():
    """Uninstalls the deployment."""
    _check_env_vars_present()
    out = sh.helm.uninstall(os.getenv(EnvVar.DATAFOLD_DEPLOY_NAME), _fg=True)
    print(out)


@dev.command()
def delete():
    """Deletes the deployment."""
    _check_env_vars_present()
    out = sh.helm.delete(os.getenv(EnvVar.DATAFOLD_DEPLOY_NAME), _fg=True)
    print(out)


@dev.command()
def render():
    """Renders all charts to console output for validation."""
    _check_env_vars_present()
    args = ['--debug']
    args.extend(_common_args())
    out = sh.helm.template(args, _fg=True)
    print(out)
