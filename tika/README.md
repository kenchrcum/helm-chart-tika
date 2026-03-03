# Apache Tika Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/tika)](https://artifacthub.io/packages/helm/kenchrcum/tika)
[![Helm Version](https://img.shields.io/badge/helm-v3.0%2B-blue)](https://helm.sh)
[![Kubernetes Version](https://img.shields.io/badge/kubernetes-1.19%2B-blue)](https://kubernetes.io)
[![License](https://img.shields.io/badge/license-Apache%202.0-green)](../../LICENSE)

A production-ready Helm chart for deploying [Apache Tika Server](https://tika.apache.org/) on Kubernetes. Tika detects and extracts metadata and text from over 1,000 different file types (PDF, DOCX, images via OCR, etc.) via a simple HTTP REST API.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Configuration](#configuration)
- [Values Reference](#values-reference)
- [Examples](#examples)
- [Monitoring](#monitoring)
- [Security](#security)
- [CI/CD](#cicd)
- [Troubleshooting](#troubleshooting)
- [Upgrade from Upstream](#upgrade-from-upstream)

---

## Overview

### Why this chart?

This chart improves upon the upstream [apache/tika-helm](https://github.com/apache/tika-helm) chart with:

| Feature | Upstream | This Chart |
|---------|----------|------------|
| Startup probe | ❌ | ✅ (critical for JVM warmup) |
| PodDisruptionBudget | ❌ | ✅ |
| ServiceMonitor / PodMonitor | ❌ | ✅ |
| Init containers / Sidecars | ❌ | ✅ |
| `allowPrivilegeEscalation` default | `true` | `false` |
| `seccompProfile` | ❌ | ✅ RuntimeDefault |
| Autoscaling behavior policies | ❌ | ✅ |
| Network policy egress + DNS | ❌ | ✅ |
| `values.schema.json` validation | ❌ | ✅ |
| Published via GitHub Pages | ❌ | ✅ |

### Architecture

```
Client → Tika Service (ClusterIP:9998) → Tika Pod (JVM)
                                         ├── /tmp (emptyDir, writable)
                                         ├── /tika-config (ConfigMap, optional)
                                         └── /tika-extras (extra JARs, optional)
```

---

## Quick Start

```bash
helm repo add kenchrcum-tika https://kenchrcum.github.io/helm-chart-tika
helm repo update
helm install tika kenchrcum-tika/tika
```

Then verify the deployment:

```bash
kubectl get pods -l app.kubernetes.io/name=tika
kubectl port-forward svc/tika 9998:9998
curl http://localhost:9998/version
# → Apache Tika 3.2.3.0
```

---

## Installation

### From Helm Repository (recommended)

```bash
helm repo add kenchrcum-tika https://kenchrcum.github.io/helm-chart-tika
helm install tika kenchrcum-tika/tika --namespace tika --create-namespace
```

### From Source

```bash
git clone https://github.com/kenchrcum/helm-chart-tika.git
helm install tika ./helm-chart-tika/tika
```

### With Custom Values

```bash
helm install tika kenchrcum-tika/tika \
  --namespace tika \
  --create-namespace \
  --set tika.fullImage=true \
  --set resources.limits.memory=4Gi
```

---

## Configuration

### Image Variants

Apache Tika ships two image variants:

| Variant | Tag Pattern | Size | Includes |
|---------|-------------|------|----------|
| Full (default) | `3.2.3.0-full` | ~1.5 GB | Tesseract OCR, GDAL, ImageMagick, fonts |
| Minimal | `3.2.3.0` | ~400 MB | Tika core only |

Control this with `tika.fullImage` (default: `true`). To use the minimal image:

```yaml
tika:
  fullImage: false
```

### Custom Tika Configuration

Mount a `tika-config.xml` via a ConfigMap:

```yaml
tika:
  config: |
    <?xml version="1.0" encoding="UTF-8"?>
    <properties>
      <parsers>
        <parser class="org.apache.tika.parser.DefaultParser">
          <parser-exclude class="org.apache.tika.parser.ocr.TesseractOCRParser"/>
        </parser>
      </parsers>
    </properties>
```

When `tika.config` is set, the chart automatically:
1. Creates a ConfigMap with the XML content
2. Mounts it at `/tika-config/tika-config.xml`
3. Passes `-c /tika-config/tika-config.xml` to the Tika process

### JVM Tuning

```yaml
tika:
  javaOpts: "-Xmx4g -Xms1g -XX:+UseG1GC"

resources:
  requests:
    memory: 2Gi
  limits:
    memory: 6Gi
```

---

## Values Reference

### Core

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Tika pod replicas | `1` |
| `image.repository` | Docker image repository | `apache/tika` |
| `image.tag` | Image tag override (empty = auto from appVersion) | `""` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `imagePullSecrets` | Registry pull secrets | `[]` |
| `nameOverride` | Partial name override | `""` |
| `fullnameOverride` | Full name override | `""` |

### Tika Server

| Parameter | Description | Default |
|-----------|-------------|---------|
| `tika.fullImage` | Use full image variant (OCR, GDAL, fonts) | `true` |
| `tika.config` | Custom `tika-config.xml` content | `""` |
| `tika.additionalConfigs` | Extra config files in the ConfigMap | `{}` |
| `tika.javaOpts` | JVM options (e.g., `-Xmx2g -XX:+UseG1GC`) | `""` |
| `tika.cors` | CORS origins (`*` or comma-separated list) | `""` |
| `tika.logLevel` | Tika Server log level | `"info"` |

### ServiceAccount

| Parameter | Description | Default |
|-----------|-------------|---------|
| `serviceAccount.create` | Create a dedicated service account | `true` |
| `serviceAccount.annotations` | Annotations for the service account | `{}` |
| `serviceAccount.name` | Name override (auto-generated if empty) | `""` |

### Pod

| Parameter | Description | Default |
|-----------|-------------|---------|
| `podAnnotations` | Annotations added to every pod | `{}` |
| `podLabels` | Labels added to every pod | `{}` |
| `podSecurityContext.runAsNonRoot` | Enforce non-root execution | `true` |
| `podSecurityContext.runAsUser` | UID (matches Tika image: `35002`) | `35002` |
| `podSecurityContext.runAsGroup` | GID | `35002` |
| `podSecurityContext.fsGroup` | Filesystem group | `35002` |

### Security Context (Container)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `securityContext.readOnlyRootFilesystem` | Read-only root (writable `/tmp` via emptyDir) | `true` |
| `securityContext.allowPrivilegeEscalation` | Prevent privilege escalation | `false` |
| `securityContext.capabilities.drop` | Drop all Linux capabilities | `["ALL"]` |
| `securityContext.seccompProfile.type` | Seccomp profile | `RuntimeDefault` |

### Service

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.enabled` | Create a Service resource | `true` |
| `service.type` | Service type (`ClusterIP`, `NodePort`, `LoadBalancer`) | `ClusterIP` |
| `service.port` | Service port | `9998` |
| `service.annotations` | Annotations for the service | `{}` |

### Ingress

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Create an Ingress resource | `false` |
| `ingress.className` | Ingress class name | `""` |
| `ingress.annotations` | Ingress annotations | `{}` |
| `ingress.hosts` | Host/path rules | `[{host: tika.local, paths: [{/,Prefix}]}]` |
| `ingress.tls` | TLS configuration | `[]` |

### Resources

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resources.requests.cpu` | CPU request | `500m` |
| `resources.requests.memory` | Memory request | `1Gi` |
| `resources.limits.cpu` | CPU limit | `"2"` |
| `resources.limits.memory` | Memory limit | `2Gi` |

### Probes

| Parameter | Description | Default |
|-----------|-------------|---------|
| `startupProbe.initialDelaySeconds` | Delay before startup probe starts | `10` |
| `startupProbe.periodSeconds` | Startup probe interval | `5` |
| `startupProbe.failureThreshold` | Max failures before restart (120s total) | `24` |
| `livenessProbe.periodSeconds` | Liveness check interval | `30` |
| `readinessProbe.periodSeconds` | Readiness check interval | `10` |

All probes check `GET /version` on the `http` named port (9998).

### Autoscaling

| Parameter | Description | Default |
|-----------|-------------|---------|
| `autoscaling.enabled` | Enable HorizontalPodAutoscaler | `false` |
| `autoscaling.minReplicas` | Minimum replicas | `1` |
| `autoscaling.maxReplicas` | Maximum replicas | `10` |
| `autoscaling.targetCPUUtilizationPercentage` | CPU target | `80` |
| `autoscaling.targetMemoryUtilizationPercentage` | Memory target | `80` |
| `autoscaling.behavior` | Scale-up/down behavior policies | `{}` |

### Pod Disruption Budget

| Parameter | Description | Default |
|-----------|-------------|---------|
| `podDisruptionBudget.enabled` | Create a PodDisruptionBudget | `false` |
| `podDisruptionBudget.minAvailable` | Min available pods or percentage | `null` |
| `podDisruptionBudget.maxUnavailable` | Max unavailable pods or percentage | `null` |

### Prometheus Monitoring

> **Note:** Tika does not natively expose Prometheus metrics. These resources are
> useful when adding a JMX exporter sidecar. See [Monitoring](#monitoring).

| Parameter | Description | Default |
|-----------|-------------|---------|
| `serviceMonitor.enabled` | Create a ServiceMonitor | `false` |
| `serviceMonitor.interval` | Scrape interval | `30s` |
| `serviceMonitor.scrapeTimeout` | Scrape timeout | `10s` |
| `serviceMonitor.path` | Metrics path | `/metrics` |
| `serviceMonitor.labels` | Extra labels (e.g., `release: prometheus`) | `{}` |
| `podMonitor.enabled` | Create a PodMonitor | `false` |
| `podMonitor.interval` | Scrape interval | `30s` |
| `podMonitor.scrapeTimeout` | Scrape timeout | `10s` |
| `podMonitor.path` | Metrics path | `/metrics` |
| `podMonitor.labels` | Extra labels | `{}` |

### Network Policy

| Parameter | Description | Default |
|-----------|-------------|---------|
| `networkPolicy.enabled` | Create a NetworkPolicy | `false` |
| `networkPolicy.policyTypes` | Policy types to enforce | `[Ingress, Egress]` |
| `networkPolicy.namespaceIsolation` | Restrict to same namespace only | `true` |
| `networkPolicy.namespaceLabel.key` | Namespace label key for isolation | `kubernetes.io/metadata.name` |
| `networkPolicy.ingress.ingressControllers` | Allow from ingress-controller namespace | `false` |
| `networkPolicy.ingress.ingressNamespace` | Ingress controller namespace name | `ingress-nginx` |
| `networkPolicy.ingress.monitoring` | Allow from monitoring namespace | `false` |
| `networkPolicy.ingress.monitoringNamespace` | Monitoring namespace name | `monitoring` |

### Extra JARs (`tikaExtras`)

Mount additional JARs at `/tika-extras/` to extend Tika's classpath:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `tikaExtras.enabled` | Enable the extra JARs volume | `false` |
| `tikaExtras.type` | Volume type: `emptyDir`, `pvc` | `emptyDir` |
| `tikaExtras.emptyDir.sizeLimit` | emptyDir size limit | `1Gi` |
| `tikaExtras.pvc.storageClass` | PVC storage class | `""` |
| `tikaExtras.pvc.size` | PVC size | `2Gi` |
| `tikaExtras.pvc.existingClaim` | Use an existing PVC | `""` |

### Extensibility

| Parameter | Description | Default |
|-----------|-------------|---------|
| `extraEnv` | Extra env vars for the Tika container | `[]` |
| `extraVolumeMounts` | Extra volume mounts for the Tika container | `[]` |
| `extraVolumes` | Extra volumes for the pod | `[]` |
| `initContainers` | Init containers | `[]` |
| `sidecars` | Sidecar containers | `[]` |

### Scheduling

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nodeSelector` | Node selector | `{}` |
| `tolerations` | Tolerations | `[]` |
| `affinity` | Affinity rules | `{}` |
| `topologySpreadConstraints` | Topology spread constraints | `[]` |

---

## Examples

### Minimal Installation

```yaml
# minimal.yaml
tika:
  fullImage: false  # ~400 MB instead of ~1.5 GB
resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: "1"
    memory: 1Gi
```

### High-Availability Production Deployment

```yaml
# ha-production.yaml
replicaCount: 3

tika:
  fullImage: true
  javaOpts: "-Xmx3g -Xms1g -XX:+UseG1GC"

resources:
  requests:
    cpu: 1
    memory: 2Gi
  limits:
    cpu: "4"
    memory: 4Gi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300

podDisruptionBudget:
  enabled: true
  minAvailable: 2

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: tika
```

### Ingress with TLS (cert-manager)

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
  hosts:
    - host: tika.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: tika-tls
      hosts:
        - tika.example.com
```

### Custom OCR Configuration

```yaml
tika:
  fullImage: true  # Required for OCR
  config: |
    <?xml version="1.0" encoding="UTF-8"?>
    <properties>
      <parsers>
        <parser class="org.apache.tika.parser.pdf.PDFParser">
          <params>
            <param name="ocrStrategy" type="string">auto</param>
            <param name="ocrDPI" type="int">300</param>
          </params>
        </parser>
      </parsers>
    </properties>
```

### Network Isolation

```yaml
networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress
  namespaceIsolation: true   # Only same-namespace pods can reach Tika
  ingress:
    ingressControllers: true   # Allow external traffic via nginx-ingress
    ingressNamespace: ingress-nginx
    monitoring: true           # Allow Prometheus scraping
    monitoringNamespace: monitoring
```

### JMX Exporter Sidecar (Prometheus Metrics)

```yaml
sidecars:
  - name: jmx-exporter
    image: bitnami/jmx-exporter:0.20.0
    ports:
      - name: metrics
        containerPort: 5556
    args:
      - "5556"
      - /config/jmx-config.yaml
    volumeMounts:
      - name: jmx-config
        mountPath: /config

extraVolumes:
  - name: jmx-config
    configMap:
      name: tika-jmx-config

podMonitor:
  enabled: true
  interval: 30s
  labels:
    release: prometheus
```

---

## Monitoring

Tika Server does not natively expose Prometheus metrics. The `serviceMonitor` and
`podMonitor` resources are included for teams using a JMX exporter sidecar.

To monitor JVM health without metrics, consider scraping the `/version` endpoint
as a black-box probe via Prometheus' `blackbox_exporter`.

---

## Security

The chart enforces secure defaults out of the box:

| Control | Setting |
|---------|---------|
| User/Group | `35002:35002` (non-root, matches Tika image) |
| Privilege escalation | Disabled (`allowPrivilegeEscalation: false`) |
| Linux capabilities | All dropped |
| Seccomp profile | `RuntimeDefault` |
| Root filesystem | Read-only (writable `/tmp` via emptyDir) |
| Service account | Dedicated, auto-created, no extra RBAC |

---

## CI/CD

This chart uses [chart-releaser](https://github.com/helm/chart-releaser) to
publish releases to GitHub Pages.

### GitHub Actions Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `helm-lint-test.yml` | PR / push to `main` touching `tika/**` | Lint + template all CI values files |
| `helm-release.yml` | Push to `main` touching `tika/**` | Package + publish to GitHub Pages |
| `setup-pages.yml` | Manual (`workflow_dispatch`) | One-time: create `gh-pages` branch |

### Local Testing

```bash
bash tika/scripts/test-chart.sh
```

This mirrors the CI steps: lint, template with all CI values files, schema validation.

---

## Troubleshooting

### Pod is stuck in Pending

Check resource availability and node tolerations:

```bash
kubectl describe pod -l app.kubernetes.io/name=tika
```

### Pod fails to start (CrashLoopBackOff)

JVM startup can take 10–30 seconds. The startup probe allows up to 120 seconds
(`24 × 5s`). To increase the window:

```yaml
startupProbe:
  failureThreshold: 36  # 3 minutes
```

Check logs:

```bash
kubectl logs -l app.kubernetes.io/name=tika --previous
```

### Out of memory (OOMKilled)

Increase resources and set JVM heap proportionally (leave ~512 MB headroom):

```yaml
tika:
  javaOpts: "-Xmx6g"
resources:
  limits:
    memory: 7Gi
```

### Connection refused

```bash
kubectl get svc -l app.kubernetes.io/name=tika
kubectl port-forward svc/tika 9998:9998
curl http://localhost:9998/version
```

---

## Upgrade from Upstream

If migrating from [apache/tika-helm](https://github.com/apache/tika-helm):

| Upstream Key | This Chart Key | Notes |
|-------------|---------------|-------|
| `image.tag` | `image.tag` | Same |
| `replicaCount` | `replicaCount` | Same |
| `networkPolicy.ingressSelectorLabel` | `networkPolicy.namespaceLabel.key` | Restructured |
| `env` | `extraEnv` | Renamed |
| *(not present)* | `tika.fullImage` | New — auto-selects `-full` tag |
| *(not present)* | `startupProbe` | New — critical for JVM warmup |
| *(not present)* | `podDisruptionBudget` | New |

---

## Requirements

- **Kubernetes**: 1.19+
- **Helm**: 3.0+
- For `serviceMonitor`/`podMonitor`: [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) installed
- For `networkPolicy`: A CNI that supports NetworkPolicy (e.g., Calico, Cilium)

---

## License

Apache License 2.0 — see the [LICENSE](../../LICENSE) file for details.

## Links

- [Apache Tika Documentation](https://tika.apache.org/)
- [Tika Docker Images](https://github.com/apache/tika-docker)
- [Helm Chart Repository](https://kenchrcum.github.io/helm-chart-tika)
- [Source Code](https://github.com/kenchrcum/helm-charts)