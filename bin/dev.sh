#!/bin/bash

check_environment_variable() {
  local variable_name="$1"

  if [ -z "${!variable_name}" ]; then
    echo "Error: Environment variable '$variable_name' is not set."
    exit 1
  fi
}

# The deploy name is a name chosen by the k8s admin to deploy this application
check_environment_variable "DATAFOLD_DEPLOY_NAME"
# The DB hostpath is where local postgres/redis data is stored
# (DEV only)
check_environment_variable "DATAFOLD_DB_HOSTPATH"

if [ -z "$DATAFOLD_K8S_SECRETFILE" ]; then
   DATAFOLD_K8S_SECRETFILE=secrets/secrets.yaml
fi

echo "Using ${DATAFOLD_K8S_SECRETFILE}"

# Do not use TAG yet, because that's only when we use the application container.
# check_environment_variable "TAG"

# Check if a command is provided as an argument
if [ $# -eq 0 ]; then
  echo "Error: Please provide a command."
  echo "install: Installs the application."
  echo "upgrade: Upgrades the installation."
  echo "uninstall: Uninstalls the application."
  exit 1
fi

# Determine which function to run based on the provided command
case "$1" in
  "install")
    helm upgrade --install $DATAFOLD_DEPLOY_NAME ./charts/datafold --set global.hostPath=$DATAFOLD_DB_HOSTPATH -f $DATAFOLD_K8S_SECRETFILE
    ;;
  "upgrade")
    helm upgrade $DATAFOLD_DEPLOY_NAME ./charts/datafold --set global.hostPath=$DATAFOLD_DB_HOSTPATH -f $DATAFOLD_K8S_SECRETFILE
    ;;
  "uninstall")
    helm uninstall $DATAFOLD_DEPLOY_NAME
    ;;
  "test")
    helm template --debug --set global.hostPath=$DATAFOLD_DB_HOSTPATH $DATAFOLD_DEPLOY_NAME ./charts/datafold -f $DATAFOLD_K8S_SECRETFILE
    ;;
  *)
    echo "Error: Unknown command '$1'."
    exit 1
    ;;
esac
