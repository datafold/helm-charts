# Getting started

Official helm charts for deploying datafold into k8s.

This repository is in development and the instructions for installation and
upgrades will be added later.

### Install from our helm repo

```
helm repo add datafold https://charts.datafold.com
helm upgrade --namespace=datafold --create-namespace --install datafold datafold/datafold --version 0.1.0
```
