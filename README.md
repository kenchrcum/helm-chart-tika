# helm-chart-tika

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/kenchrcum-tika)](https://artifacthub.io/packages/helm/kenchrcum-tika/tika)
[![Release Helm Chart](https://github.com/kenchrcum/helm-chart-tika/actions/workflows/helm-release.yml/badge.svg)](https://github.com/kenchrcum/helm-chart-tika/actions/workflows/helm-release.yml)
[![Lint and Test](https://github.com/kenchrcum/helm-chart-tika/actions/workflows/helm-lint-test.yml/badge.svg)](https://github.com/kenchrcum/helm-chart-tika/actions/workflows/helm-lint-test.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

A production-ready Helm chart for [Apache Tika Server](https://tika.apache.org/) —
a content analysis toolkit that detects and extracts metadata and text from over
1,000 different file types (PDF, DOCX, images via OCR, etc.) via a simple HTTP REST API.

---

## Add the Helm Repository

```bash
helm repo add kenchrcum-tika https://kenchrcum.github.io/helm-chart-tika
helm repo update
```

## Install

```bash
helm install tika kenchrcum-tika/tika
```

Verify:

```bash
kubectl port-forward svc/tika 9998:9998
curl http://localhost:9998/version
# → Apache Tika 3.4.0
```

---

## Chart Documentation

Full configuration reference, examples, and troubleshooting: **[tika/README.md](tika/README.md)**

---

## Example Values

Ready-to-use values files for common scenarios:

| Example | Description |
|---------|-------------|
| [`tika/examples/basic-deployment.yaml`](tika/examples/basic-deployment.yaml) | Minimal deployment with full image |
| [`tika/examples/minimal-image.yaml`](tika/examples/minimal-image.yaml) | Non-OCR image (~400 MB, lower resources) |
| [`tika/examples/custom-ocr.yaml`](tika/examples/custom-ocr.yaml) | OCR tuned via `tika-config.xml` |
| [`tika/examples/high-availability.yaml`](tika/examples/high-availability.yaml) | HPA + PDB + NetworkPolicy |

```bash
helm install tika kenchrcum-tika/tika -f tika/examples/high-availability.yaml
```

---

## Key Features

| Feature | Details |
|---------|---------|
| **Image variants** | Full (OCR, GDAL, ~1.5 GB) or minimal (~400 MB) — toggled via `tika.fullImage` |
| **Secure defaults** | Non-root (`35002:35002`), read-only filesystem, all capabilities dropped, `seccompProfile: RuntimeDefault` |
| **Startup probe** | 120 s window — handles JVM warmup without spurious restarts |
| **Autoscaling** | HPA with configurable scale-up/down behavior policies |
| **PodDisruptionBudget** | Protect availability during node maintenance |
| **Prometheus** | `ServiceMonitor` and `PodMonitor` templates for Prometheus Operator |
| **NetworkPolicy** | Namespace isolation + DNS egress |
| **Custom config** | Mount `tika-config.xml` via ConfigMap; `tika-extras/` for extra JARs |
| **Schema validation** | `values.schema.json` rejects invalid inputs at install time |

---

## CI/CD

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| [Lint and Test](https://github.com/kenchrcum/helm-chart-tika/actions/workflows/helm-lint-test.yml) | Every PR and push to `master` | `helm lint`, template rendering, schema validation |
| [Release](https://github.com/kenchrcum/helm-chart-tika/actions/workflows/helm-release.yml) | Push to `master` | Package and publish to GitHub Pages via chart-releaser |
| [Setup Pages](https://github.com/kenchrcum/helm-chart-tika/actions/workflows/setup-pages.yml) | Manual dispatch | One-time initialisation of the `gh-pages` branch |

Charts are published to:  
**`https://kenchrcum.github.io/helm-chart-tika`**

---

## Local Testing

```bash
bash tika/scripts/test-chart.sh
```

Runs lint + template rendering for all CI values files in one command.

---

## Repository Structure

```text
helm-chart-tika/
├── .github/
│   ├── cr.yaml                        # chart-releaser config
│   └── workflows/
│       ├── helm-lint-test.yml
│       ├── helm-release.yml
│       └── setup-pages.yml
├── tika/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values.schema.json
│   ├── README.md
│   ├── examples/                      # Ready-to-use values files
│   ├── scripts/test-chart.sh          # Local test runner
│   ├── templates/                     # Kubernetes resource templates
│   └── tests/                         # CI values files
├── docs/planning/PLANNING-tika.md     # Planning document
└── README.md                          # This file
```

---

## Requirements

- Kubernetes 1.19+
- Helm 3.0+
- For `serviceMonitor`/`podMonitor`: [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
- For `networkPolicy`: CNI with NetworkPolicy support (Calico, Cilium, etc.)

---

## License

[Apache License 2.0](LICENSE)

## Links

- [Apache Tika Documentation](https://tika.apache.org/)
- [Tika Docker Images](https://github.com/apache/tika-docker)
- [Artifact Hub](https://artifacthub.io/packages/helm/kenchrcum-tika/tika)
- [Helm Repository](https://kenchrcum.github.io/helm-chart-tika)
