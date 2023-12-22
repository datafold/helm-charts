from concurrent.futures import ThreadPoolExecutor
import dataclasses
import json
from pprint import pprint
import sys
import time

import sh
import typer
from typer import Option, Typer

from typing import Annotated


LIST_OF_WORKERS_TO_KILL = ["catalog", "lineage", "singletons"]


@dataclasses.dataclass(frozen=True)
class DeploymentMeta:
    deployment_name: str
    image_name: str
    old_tag: str
    container_name: str
    spec_replicas: int
    running_replicas: int
    timeout_ms: int


upgrade = Typer(no_args_is_help=True, help='Commands useful for manual operations.')


def _fail(reason: str):
    print(reason)
    sys.exit(-1)


def _clean_output(output: str, default: str = None) -> str:
    cleaned = output.replace("'", "")
    if not cleaned and default:
        return default
    return cleaned


def _check_number(deployment_name: str, json_path: str) -> int:
    output = _clean_output(
        sh.kubectl.get.deployment(deployment_name, f"-o=jsonpath='{{{json_path}}}'"),
        "0",
    )
    return int(output)


def _clean_list_output(list_output: str) -> list[str]:
    output = []
    for line in list_output.split('\n'):
        line = line.strip()
        if not line:
            continue
        output.append(line)
    return output


def _check_spec_replica_setting(deployment_name: str) -> int:
    return _check_number(deployment_name, ".spec.replicas")


def _check_current_running_replicas(deployment_name: str, in_ready_state: bool) -> int:
    readyReplicas = _check_number(deployment_name, ".status.readyReplicas")
    replicas = _check_number(deployment_name, ".status.replicas")
    print(f"Current running replicas for {deployment_name} is {readyReplicas}, total {replicas}")
    if in_ready_state:
        return readyReplicas
    return replicas


def _get_spec_termination_grace_period(deployment_name: str) -> int:
    return _check_number(deployment_name, ".spec.template.spec.terminationGracePeriodSeconds")


def _get_deployment_meta(deployment_name: str) -> DeploymentMeta:
    spec_replicas = _check_spec_replica_setting(deployment_name)
    running_replicas = _check_current_running_replicas(deployment_name, in_ready_state=True)

    image_name = _clean_output(
        sh.kubectl.get.deployment(
            deployment_name, "-o=jsonpath='{.spec.template.spec.containers[0].image}'"
        )
    )
    if not image_name:
        print(f"Could not discover currently running image for {deployment_name}. Aborting.")
        sys.exit(-1)

    image_name_without_tag, old_tag = image_name.split(':')
    container_name = _clean_output(
        sh.kubectl.get.deployment(
            deployment_name, "-o=jsonpath='{.spec.template.spec.containers[0].name}'"
        )
    )
    timeout = _get_spec_termination_grace_period(deployment_name)
    dm = DeploymentMeta(
        deployment_name=deployment_name,
        image_name=image_name_without_tag,
        old_tag=old_tag,
        container_name=container_name,
        spec_replicas=spec_replicas,
        running_replicas=running_replicas,
        timeout_ms=timeout * 1000,
    )
    print("Current deploy meta:")
    pprint(dataclasses.asdict(dm), sort_dicts=False)
    return dm


def _scale_down_deployment(deploy_meta: DeploymentMeta, graceful: bool = True) -> bool:
    deployment_name = deploy_meta.deployment_name
    print(f"Scaling down {deployment_name} to 0")
    sh.kubectl.scale.deploy("--replicas", "0", deployment_name)

    print(f"Waiting up to {deploy_meta.timeout_ms / 1000} seconds for the containers to go down")
    t0 = time.time()

    running_replicas = _check_current_running_replicas(deployment_name, in_ready_state=False)
    while running_replicas != 0:
        time.sleep(3)

        running_replicas = _check_current_running_replicas(deployment_name, in_ready_state=False)
        if running_replicas == 0:
            print("No more replicas are running.")
            break

        if time.time() > t0 + deploy_meta.timeout_ms:
            print(f"Timed out waiting for deployment {deployment_name} to shut down all instances.")
            return False

    return True


def _scale_up_deployment(deploy_meta: DeploymentMeta, tag: str, target_replicas: int):
    deployment_name = deploy_meta.deployment_name

    new_image = f"{deploy_meta.image_name}:{tag}"
    print(f"Setting deployment {deployment_name} image to {new_image}")
    sh.kubectl.set.image(
        f"deployment/{deployment_name}", f"{deploy_meta.container_name}={new_image}"
    )

    print(f"Scaling up {deployment_name} to {target_replicas}")
    sh.kubectl.scale.deploy("--replicas", f"{target_replicas}", deployment_name)
    running_replicas = _check_current_running_replicas(deployment_name, in_ready_state=True)
    t0 = time.time()
    # startup should be faster. Let's wait up to the value below for pulling containers, etc.
    timeout = 120
    while running_replicas != target_replicas:
        time.sleep(3)

        running_replicas = _check_current_running_replicas(deployment_name, in_ready_state=True)

        if time.time() > t0 + timeout:
            print(f"Timed out waiting for deployment {deployment_name} to start")
            return False

    return True


def _restart_deployment(deploy_meta: DeploymentMeta, tag: str):
    print("------------")
    if not deploy_meta:
        print("Deployment is empty. Skipping")
        return

    print(f"Starting to scale deployment: {deploy_meta.deployment_name}")

    deploy_meta = _get_deployment_meta(deploy_meta.deployment_name)
    _scale_down_deployment(deploy_meta)
    _scale_up_deployment(deploy_meta, tag=tag, target_replicas=deploy_meta.spec_replicas)


def _rollout_deployment(deploy_meta: DeploymentMeta, tag: str):
    print("------------")
    if not deploy_meta:
        print("Deployment is empty. Skipping")
        return

    print(f"Starting to roll out deployment: {deploy_meta.deployment_name}")

    deployment_name = deploy_meta.deployment_name
    new_image = f"{deploy_meta.image_name}:{tag}"
    print(f"Setting deployment {deployment_name} image to {new_image}")
    sh.kubectl.set.image(
        f"deployment/{deployment_name}", f"{deploy_meta.container_name}={new_image}"
    )

    t0 = time.time()
    # We would expect a new instance to be up and running in about 60 seconds
    timeout = 60
    while True:
        time.sleep(10)

        running_replicas = _check_current_running_replicas(deployment_name, in_ready_state=True)

        if running_replicas > 0:
            break

        if time.time() > t0 + timeout:
            print(f"Timed out waiting for deployment {deployment_name} to start")
            return False

    return True


def _check_needed_migs(dfshell_pod: str) -> tuple[bool, bool]:
    def wait_and_verify(db_name: str):
        needed = False
        print(f"Waiting for connectivity to {db_name}")
        _ = sh.kubectl.exec(dfshell_pod, "--", "./manage.py", db_name, "wait-for-connection")
        try:
            print(f"Checking if {db_name} is up to date")
            _ = sh.kubectl.exec(
                dfshell_pod, "--", "./manage.py", "database", "is-up-to-date", _fg=True
            )
        except sh.ErrorReturnCode as e:
            if e.exit_code == 1:
                needed = True
            else:
                raise typer.Exit(1)

        return needed

    pg_mig_needed = wait_and_verify("database")
    ch_mig_needed = wait_and_verify("clickhouse")

    print(f"Postgres needs migration: {pg_mig_needed}")
    print(f"Clickhouse needs migration: {ch_mig_needed}")

    return pg_mig_needed, ch_mig_needed


def _get_current_revision_history(dfshell_pod: str) -> list[str]:
    _ = sh.kubectl.exec(dfshell_pod, "--", "./manage.py", "database", "wait-for-connection")
    stdout = sh.kubectl.exec(dfshell_pod, "--", "./manage.py", "database", "dump-migrations")
    lines = stdout.split("\n")
    lines = [line.strip() for line in lines if line.strip() and ':' in line]
    migs = list()
    for line in lines:
        to_mig = line.split(":")[1]
        migs.append(to_mig)

    return migs


def _rollback_migrations(dfshell_pod: str, sha: str):
    try:
        _ = sh.kubectl.exec(
            dfshell_pod,
            "--",
            "./manage.py",
            "database",
            "downgrade",
            "--sha",
            sha,
            _fg=True,
        )
    except sh.ErrorReturnCode as e:
        print(e.stdout)
        print(e.stderr)
        print(str(e))
        raise typer.Exit(1)


def _upgrade_postgres(dfshell_pod: str):
    try:
        _ = sh.kubectl.exec(dfshell_pod, "--", "./manage.py", "database", "upgrade", _fg=True)
    except sh.ErrorReturnCode as e:
        print(e.stdout)
        print(e.stderr)
        print(str(e))
        raise typer.Exit(1)


def _upgrade_clickhouse(dfshell_pod: str):
    try:
        _ = sh.kubectl.exec(dfshell_pod, "--", "./manage.py", "clickhouse", "upgrade", _fg=True)
    except sh.ErrorReturnCode as e:
        print(e.stdout)
        print(e.stderr)
        print(str(e))
        raise typer.Exit(1)


def _calculate_common_base(current: list[str], new_migs: list[str]) -> str | None:
    res = next((ele for ele in current if ele in new_migs), None)
    if res != current[0]:
        return res
    # When current common point is where we are now, no rollbacks are needed
    return None


def _find_single_running_pod(req_pod_name: str) -> str | None:
    TIMEOUT = 30000
    t0 = time.time()

    print("Waiting until we have a single dfshell pod, the other is still being terminated")

    while time.time() < t0 + TIMEOUT:
        json_string_output = sh.kubectl.get.pods("-o", "json")
        pods = json.loads(json_string_output)
        count = 0

        for pod in pods['items']:
            container_name = pod['spec']['containers'][0]['name']
            if req_pod_name == container_name:
                pod_name = pod['metadata']['name']
                count += 1

        if count > 1:
            print(f"Found more than one {req_pod_name} pod")
            time.sleep(4)
        else:
            print(f"Found the one {req_pod_name} pod")
            break

    if not pod_name:
        print("No running dfshell pod found!")
        raise typer.Exit(-1)

    return pod_name


def _run_io_tasks_in_parallel(tasks):
    with ThreadPoolExecutor() as executor:
        running_tasks = [executor.submit(task) for task in tasks]
        for running_task in running_tasks:
            data = running_task.result()
            if not data:
                print("A task returned no data")
                raise typer.Exit(-1)


@upgrade.command()
def version(tag: Annotated[str, Option(help='The version to upgrade to.')]):
    """Upgrades the deployment to a new version."""
    other_deployments: set(DeploymentMeta) = set()
    all_deployments: set(DeploymentMeta) = set()

    workers_to_kill: set(DeploymentMeta) = set()
    workers_to_stop: set(DeploymentMeta) = set()
    dfshell_deployment: DeploymentMeta | None = None
    server_deployment: DeploymentMeta | None = None
    scheduler_deployment: DeploymentMeta | None = None

    t0 = time.time()

    output = _clean_output(sh.kubectl.config.view("--minify", "-o", "jsonpath='{..namespace}'"))
    if not output:
        _fail("You do not have the datafold namespace set")

    if not output.startswith("datafold"):
        _fail(f"Your current namespace is not pointing to datafold. Instead, it points to {output}")

    output = _clean_list_output(
        sh.kubectl.get.deployments("-o", "json", "-o", "custom-columns=NAME:metadata.name")
    )
    for deployment_name in output:
        if deployment_name == "NAME":
            continue

        deploy_meta = _get_deployment_meta(deployment_name)

        all_deployments.add(deploy_meta)
        if "worker" in deployment_name:
            if any(to_be_killed in deployment_name for to_be_killed in LIST_OF_WORKERS_TO_KILL):
                workers_to_kill.add(deploy_meta)
            else:
                workers_to_stop.add(deploy_meta)
            continue
        if "server" in deployment_name:
            server_deployment = deploy_meta
            continue
        if "scheduler" in deployment_name:
            scheduler_deployment = deploy_meta
            continue
        if "shell" in deployment_name:
            dfshell_deployment = deploy_meta
            continue

        other_deployments.add(deploy_meta)

    print(f"Deployments found:\n {all_deployments}")

    print("Now working out migration histories and if rollbacks should happen")

    dfshell_pod = _find_single_running_pod(req_pod_name='dfshell')
    current_mig_history = _get_current_revision_history(dfshell_pod=dfshell_pod)

    _restart_deployment(deploy_meta=dfshell_deployment, tag=tag)
    dfshell_pod = _find_single_running_pod(req_pod_name='dfshell')
    new_mig_history = _get_current_revision_history(dfshell_pod=dfshell_pod)

    common_mig_base = _calculate_common_base(current_mig_history, new_mig_history)
    if common_mig_base:
        # We need to roll back to a common migration first.
        _restart_deployment(deploy_meta=dfshell_deployment, tag=dfshell_deployment.old_tag)
        dfshell_pod = _find_single_running_pod(req_pod_name='dfshell')
        _rollback_migrations(dfshell_pod=dfshell_pod, sha=common_mig_base)
        _restart_deployment(deploy_meta=dfshell_deployment, tag=tag)
        dfshell_pod = _find_single_running_pod(req_pod_name='dfshell')
    else:
        print("Either no rollbacks are needed or too many migs to determine rollback point.")

    pg_mig_needed, ch_mig_needed = _check_needed_migs(dfshell_pod)

    if ch_mig_needed:
        _run_io_tasks_in_parallel(
            [lambda: _scale_down_deployment(deploy_meta) for deploy_meta in workers_to_stop]
        )
        # In k8s, we should probably use terminationGracePeriod correctly for correct behavior.
        _run_io_tasks_in_parallel(
            [lambda: _scale_down_deployment(deploy_meta) for deploy_meta in workers_to_kill]
        )
        _scale_down_deployment(scheduler_deployment)

        _upgrade_clickhouse(dfshell_pod=dfshell_pod)

    if pg_mig_needed:
        _upgrade_postgres(dfshell_pod=dfshell_pod)

    if ch_mig_needed:
        _scale_up_deployment(
            scheduler_deployment,
            tag=tag,
            target_replicas=scheduler_deployment.spec_replicas,
        )
        _run_io_tasks_in_parallel(
            [
                lambda: _scale_up_deployment(
                    deploy_meta, tag=tag, target_replicas=deploy_meta.spec_replicas
                )
                for deploy_meta in workers_to_kill
            ]
        )
        _run_io_tasks_in_parallel(
            [
                lambda: _scale_up_deployment(
                    deploy_meta, tag=tag, target_replicas=deploy_meta.spec_replicas
                )
                for deploy_meta in workers_to_stop
            ]
        )
    else:
        _run_io_tasks_in_parallel(
            [lambda: _rollout_deployment(deploy_meta, tag=tag) for deploy_meta in workers_to_stop]
        )
        _run_io_tasks_in_parallel(
            [lambda: _rollout_deployment(deploy_meta, tag=tag) for deploy_meta in workers_to_kill]
        )
        _rollout_deployment(scheduler_deployment, tag=tag)

    _rollout_deployment(deploy_meta=server_deployment, tag=tag)

    secs = (time.time() - t0) / 1000.0

    print(f"Rollout complete in {secs} seconds.")
