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

```
helm repo add datafold https://charts.datafold.com
helm upgrade --install datafold datafold/datafold \
  --version 0.1.0  \
  --set global.datafoldVersion="<version_tag>" \
  --set global.serverName="<access-url-on-lb>" \
  --set global.cloudProvider="aws" \
  --set global.awsTargetGroupArn="<replace-with-target-group-arn>" \
  --set global.awsLbCtrlArn="<replace-with-load-balancer-controller-role-arn>"
```
