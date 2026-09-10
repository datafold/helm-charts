# Datafold Helm Charts

> **Read-only mirror.** These charts are developed in Datafold's private operator
> repository, whose release pipeline publishes every version here: this `main` branch,
> the per-chart GitHub releases, and the `gh-pages` chart index served at
> `https://datafold.github.io/helm-charts`. Pull requests against this repository cannot
> be merged. Datafold engineers change charts in the operator repository; everyone else,
> please open an issue.

Official Helm charts for deploying Datafold into Kubernetes.

Datafold is deployed via the **Datafold Operator** (preferred) or directly with Helm values. Both methods require Temporal and PostgreSQL to be running before the Datafold application is deployed.

See **[docs/index.md](docs/index.md)** for the full deployment guide, including prerequisites, deployment options, and configuration examples.
