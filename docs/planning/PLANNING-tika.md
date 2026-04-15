# Apache Tika Helm Chart — Planning Document

> **Purpose:** Guide the implementation of a production-ready Helm chart for
> [Apache Tika Server](https://github.com/apache/tika-docker) to be published
> at `https://kenchrcum.github.io/helm-charts` for reliable document content
> analysis and extraction in Kubernetes environments.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Apache Tika Architecture Analysis](#2-apache-tika-architecture-analysis)
3. [Docker Image Variants](#3-docker-image-variants)
4. [Deployment Scenarios](#4-deployment-scenarios)
5. [Configuration Options](#5-configuration-options)
6. [Comparison with Upstream Helm Chart](#6-comparison-with-upstream-helm-chart)
7. [Helm Chart Design](#7-helm-chart-design)
8. [Repository & CI/CD Structure](#8-repository--cicd-structure)
9. [Implementation Phases](#9-implementation-phases)
10. [Testing Strategy](#10-testing-strategy)
11. [Open Questions & Decisions](#11-open-questions--decisions)

---

## 1. Project Overview

### What is Apache Tika?

Apache Tika is a content analysis toolkit that detects and extracts metadata and
text from over a thousand different file types (PDF, DOCX, PPTX, images via OCR,
etc.). Tika Server exposes this functionality as an HTTP REST API on **port 9998**,
accepting file uploads and returning extracted text, metadata, or structured content.

### Why a New Helm Chart?

The existing [apache/tika-helm](https://github.com/apache/tika-helm) chart
exists but has several shortcomings:

- **Sporadic maintenance** — releases lag behind Tika Docker image versions.
- **Missing production features** — no PodDisruptionBudget, no ServiceMonitor/PodMonitor,
  limited NetworkPolicy, no startup probes, no extra volume/env extensibility.
- **Questionable security defaults** — `allowPrivilegeEscalation: true` by default,
  `readOnlyRootFilesystem: true` without proper writable mounts (requires the
  `sec-ctx-vol` hack for `/tmp`).
- **No `values.schema.json`** — no input validation for end users.
- **Ingress template** is outdated (missing `ingressClassName`, limited path config).
- **No Helm test** included.
- **Published via JFrog Artifactory** (`https://apache.jfrog.io/artifactory/tika`)
  which may have availability concerns.

Our chart will:

- Follow Helm best practices aligned with our existing `examples/helm-chart/`
  patterns (s3-encryption-gateway).
- Add production features: PDB, ServiceMonitor, PodMonitor, NetworkPolicy with
  fine-grained control, startup probes, topology spread constraints.
- Provide secure defaults: `allowPrivilegeEscalation: false`, `seccompProfile`,
  properly mounted writable volumes.
- Be published via GitHub Pages at `https://kenchrcum.github.io/helm-charts`.

### Design Principles

The chart is designed for general-purpose Tika deployments:
- Easy to deploy as a standalone microservice accessible via Kubernetes DNS.
- Support for horizontal scaling with replicas and autoscaling.
- Flexible configuration for custom deployment scenarios.
- Production-ready defaults for resource requests, security, and health checks.

### Reference Material

| Source | URL |
|--------|-----|
| Apache Tika project | <https://tika.apache.org/> |
| Tika Server docs | <https://tika.apache.org/3.0.0/gettingstarted.html> |
| tika-docker repo | <https://github.com/apache/tika-docker> |
| tika-helm repo (upstream) | <https://github.com/apache/tika-helm> |
| DockerHub images | <https://hub.docker.com/r/apache/tika> |

| Existing example chart (this repo) | `examples/helm-chart/` (s3-encryption-gateway) |
| Existing CI examples (this repo) | `examples/github-actions/` |
| Existing planning doc (this repo) | `PLANNING-docling.md` |

---

## 2. Apache Tika Architecture Analysis

### Runtime Components

Tika Server is a **single-process Java application**:

```text
┌─────────────────────────────────────────────────┐
│                 Tika Server (JVM)                │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │  REST API │  │  Parser  │  │   Detector    │  │
│  │  :9998    │  │  Engine  │  │   Engine      │  │
│  └────┬─────┘  └────┬─────┘  └───────┬───────┘  │
│       │              │                │          │
│  ┌────┴──────────────┴────────────────┴───────┐  │
│  │            Tika Core Library                │  │
│  │  (1000+ format parsers, OCR, metadata)     │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  Optional: Tesseract OCR, GDAL (full image)     │
│  Optional: Custom config via tika-config.xml     │
│  Optional: Extra JARs via /tika-extras/          │
└─────────────────────────────────────────────────┘
```

### Key REST API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/tika` | PUT | Parse document, return extracted text |
| `/rmeta` | PUT | Parse document, return recursive metadata+text as JSON |
| `/detect/stream` | PUT | Detect MIME type of document |
| `/unpack` | PUT | Unpack contents of container documents |
| `/meta` | PUT | Extract only metadata |
| `/` | GET | Returns welcome HTML page (used for health check) |
| `/version` | GET | Returns Tika version string |

### Key Characteristics

| Property | Value |
|----------|-------|
| Default port | `9998` |
| Protocol | HTTP (no built-in TLS) |
| Health check | `GET /` returns `200 OK` with HTML welcome page |
| Version check | `GET /version` returns plain-text version string |
| User/Group (container) | `35002:35002` |
| Read-only filesystem | Supported — but needs writable `/tmp` for processing |
| Stateless | Yes — no persistent storage required |
| Concurrency | Handles concurrent requests; Java thread pool |
| Memory profile | High — 1.5-2GB minimum for full image with OCR |
| Startup time | 10-30 seconds (JVM warmup + parser initialization) |
| Multi-arch support | `linux/amd64`, `linux/arm/v7`, `linux/arm64/v8`, `linux/s390x` |

---

## 3. Docker Image Variants

Apache Tika publishes two image variants on DockerHub as `apache/tika`:

### 3.1 Minimal Image (`<version>` / `latest`)

- Contains only Apache Tika core and its Java dependencies.
- No OCR (Tesseract), no GDAL, no extra fonts.
- **Smaller image size** (~400MB).
- Suitable for text extraction from office documents, PDFs (text-based), HTML, etc.
- Tag examples: `3.3.0`, `latest`

### 3.2 Full Image (`<version>-full` / `latest-full`)

- Includes everything in minimal plus:
  - **Tesseract OCR** with language packs (English, French, German, Italian, Spanish, Japanese).
  - **GDAL** for geospatial format support.
  - **ImageMagick** for image processing.
  - **Microsoft core fonts** and other font packages.
- **Larger image size** (~1.5GB).
- Required for OCR on scanned documents and images.
- Tag examples: `3.3.0-full`, `latest-full`

### Recommended Default Image

The **full image** (`3.3.0-full`) is recommended as the default because:
- The full variant includes OCR (Tesseract), GDAL, and fonts for comprehensive document processing.
- OCR capability enables extraction from scanned documents and images.
- The additional ~1GB of image size is acceptable for the expanded functionality.
- Users can override this with the minimal image variant if size is critical.

### Version Matrix (Current)

| Tag | Tika Version | Base OS | Java |
|-----|-------------|---------|------|
| `3.3.0` | 3.3.0 | Ubuntu Plucky | OpenJDK 21 |
| `3.3.0-full` | 3.3.0 | Ubuntu Plucky | OpenJDK 21 |
| `latest` | 3.3.0 | Ubuntu Plucky | OpenJDK 21 |
| `latest-full` | 3.3.0 | Ubuntu Plucky | OpenJDK 21 |

---

## 4. Deployment Scenarios

### 4.1 Standalone Tika (Simple — Default)

A single Tika Server deployment exposed as a ClusterIP Service. This is the
most common deployment and the default for our chart.

```text
┌──────────────┐       ┌──────────────────┐
│    Client    │──────>│   Tika Service   │
│   (any app)  │ :9998 │   (ClusterIP)    │
└──────────────┘       └────────┬─────────┘
                                │
                       ┌────────▼─────────┐
                       │  Tika Deployment  │
                       │  (1+ replicas)    │
                       └──────────────────┘
```

**Use case:** Small to medium workloads; basic document extraction.

### 4.2 Tika with Custom Configuration

Tika Server can be configured via an XML configuration file (`tika-config.xml`)
that controls:
- Parser selection and exclusion
- OCR settings (strategy, DPI, language, image type)
- MIME type detection rules
- Custom parser parameters

The config is mounted via a ConfigMap and passed to Tika via the `-c` flag.

**Use case:** Customizing OCR behavior, disabling specific parsers,
adding custom MIME type rules.

### 4.3 Tika with Extra JARs

Since Tika 2.5.0.2, extra JARs can be added to the classpath by mounting
them at `/tika-extras/`. This allows adding optional components like:
- `tika-eval` metadata filter
- `jai-imageio-jpeg2000` for JPEG2000 support
- Custom parser implementations

**Use case:** Extending Tika with additional format support.

### 4.4 Tika with Horizontal Autoscaling

For high-volume document processing, Tika can be scaled horizontally since
it is stateless. Each pod processes requests independently.

```text
                       ┌──────────────────┐
                       │       HPA        │
                       │  (CPU/Memory)    │
                       └────────┬─────────┘
                                │ scales
                       ┌────────▼─────────┐
                       │  Tika Deployment  │
                       │  (2-10 replicas)  │
                       └──────────────────┘
```

**Use case:** High document throughput; batch processing pipelines.

### 4.5 Tika with Companion Services (Advanced)

The tika-docker repository includes Docker Compose examples for running Tika
alongside companion services:

| Companion | Purpose | Docker Compose File |
|-----------|---------|-------------------|
| Grobid | Scientific document parsing (academic PDFs) | `docker-compose-tika-grobid.yml` |
| TensorFlow Inception | Vision/image classification | `docker-compose-tika-vision.yml` |
| NER models | Named Entity Recognition | `docker-compose-tika-ner.yml` |

**Decision:** These companion services are **out of scope** for the initial
chart. They each require their own images and significant configuration.
Users requiring these can deploy them separately and configure Tika to connect
via the custom `tika-config.xml`. We will document this as an advanced pattern.

---

## 5. Configuration Options

### 5.1 Tika Server Command-Line Arguments

The Tika Server Docker entrypoint accepts arguments passed after the image name:

| Argument | Description |
|----------|-------------|
| `-c <path>` / `--config <path>` | Path to tika-config.xml |
| `-h <host>` | Host to bind (default: `0.0.0.0` in container) |
| `-p <port>` | Port to bind (default: `9998`) |
| `-l <log-level>` | Log level (default: `info`) |
| `-s` | Enable server status endpoint |
| `--cors <origins>` | Enable CORS with specified origins |

### 5.2 Tika Configuration XML (`tika-config.xml`)

Full XML configuration for the Tika server. Key sections:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<properties>
  <!-- Parser configuration -->
  <parsers>
    <parser class="org.apache.tika.parser.DefaultParser">
      <mime-exclude>image/jpeg</mime-exclude>
      <parser-exclude class="org.apache.tika.parser.ocr.TesseractOCRParser"/>
    </parser>
  </parsers>

  <!-- OCR configuration (for full image) -->
  <parsers>
    <parser class="org.apache.tika.parser.pdf.PDFParser">
      <params>
        <param name="ocrStrategy" type="string">auto</param>
        <param name="ocrDPI" type="int">300</param>
      </params>
    </parser>
  </parsers>

  <!-- Auto-detection configuration -->
  <autoDetectParserConfig>
    <params>
      <spoolToDisk>-1</spoolToDisk>
      <outputThreshold>-1</outputThreshold>
    </params>
  </autoDetectParserConfig>
</properties>
```

### 5.3 Additional Configuration Files

The upstream chart supports `additionalConfigs` which are extra files mounted
alongside `tika-config.xml` in the same ConfigMap. This is useful for:
- Custom MIME type definitions (`custom-mimetypes.xml`)
- Custom parser configurations referenced by the main config

### 5.4 Environment Variables

Tika Server itself does not use environment variables for configuration (it
relies on the XML config and CLI flags). However, the JVM can be configured:

| Variable | Purpose |
|----------|---------|
| `JAVA_OPTS` | JVM options (heap size, GC settings, etc.) |
| `TIKA_VERSION` | Set automatically in the Docker image |

### 5.5 Extra JARs Volume

Mount additional JARs at `/tika-extras/` to add them to the classpath.
This is baked into the Docker entrypoint:

```sh
exec java -cp "/tika-server-standard-${TIKA_VERSION}.jar:/tika-extras/*" \
  org.apache.tika.server.core.TikaServerCli -h 0.0.0.0 $0 $@
```

---

## 6. Comparison with Upstream Helm Chart

### What the Upstream Chart Does Well

| Feature | Status |
|---------|--------|
| Basic deployment | ✅ Working |
| ConfigMap for tika-config.xml | ✅ Working |
| Additional config files | ✅ Working |
| Service (ClusterIP) | ✅ Working |
| Ingress | ✅ Basic |
| HPA (autoscaling) | ✅ Working |
| NetworkPolicy | ✅ Basic (label-based) |
| ServiceAccount | ✅ Working |
| Liveness/Readiness probes | ✅ Working (HTTP + TCP options) |
| Security context | ✅ Present |
| Topology spread constraints | ✅ Working |
| `values.schema.json` | ✅ Present |
| `env` passthrough | ✅ Working |

### What the Upstream Chart Lacks (Our Improvements)

| Feature | Upstream | Our Chart |
|---------|----------|-----------|
| Startup probe | ❌ Missing | ✅ Needed — JVM startup is slow |
| PodDisruptionBudget | ❌ Missing | ✅ |
| ServiceMonitor (Prometheus) | ❌ Missing | ✅ |
| PodMonitor (Prometheus) | ❌ Missing | ✅ |
| Extra volumes/mounts | ❌ Missing | ✅ `extraVolumes`, `extraVolumeMounts` |
| Extra env vars | ❌ Partial (`env` list) | ✅ `extraEnv` with proper naming |
| Init containers | ❌ Missing | ✅ `initContainers` |
| Sidecar containers | ❌ Missing | ✅ `sidecars` |
| Pod labels | ❌ Missing | ✅ `podLabels` |
| Service annotations | ❌ Missing | ✅ |
| Service toggle | ❌ Always created | ✅ `service.enabled` |
| Ingress className | ❌ Missing field | ✅ Proper `ingressClassName` |
| Ingress path types | ❌ Limited | ✅ Full path/pathType per host |
| NetworkPolicy egress | ❌ Missing | ✅ DNS + configurable egress |
| NetworkPolicy namespace isolation | ❌ Missing | ✅ |
| `seccompProfile` | ❌ Missing | ✅ `RuntimeDefault` |
| `allowPrivilegeEscalation` | ⚠️ `true` default | ✅ `false` default |
| Writable `/tmp` via emptyDir | ⚠️ Hardcoded `sec-ctx-vol` | ✅ Clean implementation |
| Extra JARs PVC/volume | ❌ Missing | ✅ `tikaExtras` volume support |
| JVM options configuration | ❌ Missing | ✅ `javaOpts` value |
| CORS configuration | ❌ Missing | ✅ CLI flag support |
| Helm test | ❌ Missing | ✅ Test pod |
| Autoscaling behavior | ❌ Missing | ✅ Scale-up/down policies |
| `topologySpreadConstraints` | ✅ | ✅ |
| Chart published on GitHub Pages | ❌ JFrog Artifactory | ✅ GitHub Pages |

---

## 7. Helm Chart Design

### 7.1 Directory Layout

```text
helm-charts/
├── .github/
│   ├── cr.yaml                     # chart-releaser config
│   └── workflows/
│       ├── helm-lint-test.yml      # PR: lint + template + unittest
│       ├── helm-release.yml        # Push to master: package + release via chart-releaser
│       └── setup-pages.yml         # One-time: create gh-pages branch
├── charts/
│   └── tika/                       # The actual chart
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values.schema.json
│       ├── README.md
│       ├── .helmignore
│       ├── templates/
│       │   ├── NOTES.txt
│       │   ├── _helpers.tpl
│       │   ├── configmap.yaml           # tika-config.xml + additional configs
│       │   ├── deployment.yaml
│       │   ├── hpa.yaml
│       │   ├── ingress.yaml
│       │   ├── networkpolicy.yaml
│       │   ├── poddisruptionbudget.yaml
│       │   ├── podmonitor.yaml
│       │   ├── service.yaml
│       │   ├── serviceaccount.yaml
│       │   ├── servicemonitor.yaml
│       │   └── tests/
│       │       └── test-connection.yaml
│       └── tests/                       # CI values files
│           ├── ci-default.yaml
│           ├── ci-custom-config.yaml
│           ├── ci-full-features.yaml
│           └── ci-minimal-image.yaml
├── examples/                       # Reference examples (existing)
│   ├── github-actions/
│   └── helm-chart/
├── PLANNING-tika.md                # This document
├── PLANNING-docling.md             # Docling planning (existing)
└── README.md
```

### 7.2 `Chart.yaml`

```yaml
apiVersion: v2
name: tika
description: >-
  A Helm chart for Apache Tika Server — a content analysis toolkit that detects
  and extracts metadata and text from over a thousand different file types.
type: application
version: 0.1.0
appVersion: "3.3.0"
home: https://github.com/kenchrcum/helm-charts
sources:
  - https://github.com/kenchrcum/helm-charts
  - https://github.com/apache/tika-docker
  - https://github.com/apache/tika-helm
keywords:
  - tika
  - apache-tika
  - document-parsing
  - text-extraction
  - ocr
  - pdf
  - content-analysis
maintainers:
  - name: kenchrcum
    url: https://github.com/kenchrcum
icon: https://tika.apache.org/tika.png
annotations:
  artifacthub.io/category: integration-delivery
  artifacthub.io/license: Apache-2.0
  artifacthub.io/links: |
    - name: Apache Tika
      url: https://tika.apache.org/
    - name: Tika Docker
      url: https://github.com/apache/tika-docker
```

### 7.3 `values.yaml` — Full Structure

```yaml
# -- Number of Tika pod replicas to deploy
replicaCount: 1

image:
  # -- Docker image repository for Apache Tika
  repository: apache/tika
  # -- Image pull policy
  pullPolicy: IfNotPresent
  # -- Image tag (defaults to appVersion from Chart.yaml with "-full" suffix)
  tag: ""

# -- Secrets for pulling images from a private registry
imagePullSecrets: []
# -- Override the name of the chart
nameOverride: ""
# -- Override the full name of the release
fullnameOverride: ""

# ---------------------------------------------------------
# Tika Server Configuration
# ---------------------------------------------------------
tika:
  # -- Use the full image variant (with OCR, GDAL, fonts).
  # When true and image.tag is empty, appends "-full" to the appVersion.
  # Set to false for the minimal image.
  fullImage: true

  # -- Custom Tika configuration XML (tika-config.xml).
  # When set, creates a ConfigMap and passes -c flag to Tika.
  # See: https://tika.apache.org/3.0.0/configuring.html
  # Example:
  #   config: |
  #     <?xml version="1.0" encoding="UTF-8"?>
  #     <properties>
  #       <parsers>
  #         <parser class="org.apache.tika.parser.DefaultParser">
  #           <parser-exclude class="org.apache.tika.parser.ocr.TesseractOCRParser"/>
  #         </parser>
  #       </parsers>
  #     </properties>
  config: ""

  # -- Additional configuration files to mount alongside tika-config.xml.
  # Each key becomes a file in /tika-config/.
  # Example:
  #   additionalConfigs:
  #     custom-mimetypes.xml: |
  #       <?xml version="1.0" encoding="UTF-8"?>
  #       <mime-info>
  #         <mime-type type="application/pdf">
  #           <glob pattern="*.pdf"/>
  #         </mime-type>
  #       </mime-info>
  additionalConfigs: {}

  # -- JVM options for the Tika Server process.
  # Example: "-Xmx2g -Xms512m -XX:+UseG1GC"
  javaOpts: ""

  # -- CORS origins to allow (passed as --cors flag).
  # Set to "*" for all origins, or a comma-separated list.
  cors: ""

  # -- Log level for Tika Server
  logLevel: "info"

# ---------------------------------------------------------
# Service Account
# ---------------------------------------------------------
serviceAccount:
  # -- Create a service account
  create: true
  # -- Annotations to add to the service account
  annotations: {}
  # -- The name of the service account (auto-generated if empty)
  name: ""

# ---------------------------------------------------------
# Pod Configuration
# ---------------------------------------------------------
# -- Annotations to add to pods
podAnnotations: {}
# -- Labels to add to pods
podLabels: {}

podSecurityContext:
  # -- Run pod as non-root
  runAsNonRoot: true
  # -- User ID (matches Tika Docker image UID)
  runAsUser: 35002
  # -- Group ID (matches Tika Docker image GID)
  runAsGroup: 35002
  # -- Filesystem group
  fsGroup: 35002

securityContext:
  capabilities:
    drop:
      - ALL
  # -- Read-only root filesystem (Tika needs writable /tmp via emptyDir)
  readOnlyRootFilesystem: true
  # -- Disallow privilege escalation
  allowPrivilegeEscalation: false
  seccompProfile:
    type: RuntimeDefault

# ---------------------------------------------------------
# Service
# ---------------------------------------------------------
service:
  # -- Create a Service resource
  enabled: true
  # -- Service type (ClusterIP, NodePort, LoadBalancer)
  type: ClusterIP
  # -- Service port
  port: 9998
  # -- Annotations for the service
  annotations: {}

# ---------------------------------------------------------
# Ingress
# ---------------------------------------------------------
ingress:
  # -- Enable ingress
  enabled: false
  # -- Ingress class name
  className: ""
  # -- Annotations for the ingress
  annotations: {}
    # kubernetes.io/ingress.class: nginx
    # cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: tika.local
      paths:
        - path: /
          pathType: Prefix
  # -- TLS configuration
  tls: []
  #  - secretName: tika-tls
  #    hosts:
  #      - tika.local

# ---------------------------------------------------------
# Resources
# ---------------------------------------------------------
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: "2"
    memory: 2Gi

# ---------------------------------------------------------
# Probes
# ---------------------------------------------------------
startupProbe:
  httpGet:
    path: /version
    port: http
  # -- Tika JVM startup can be slow; allow up to 120s (24 * 5s)
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 24
  timeoutSeconds: 5

livenessProbe:
  httpGet:
    path: /version
    port: http
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /version
    port: http
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

# ---------------------------------------------------------
# Autoscaling
# ---------------------------------------------------------
autoscaling:
  # -- Enable HorizontalPodAutoscaler
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80
  # -- Autoscaling behavior policies
  behavior: {}
  #   scaleDown:
  #     stabilizationWindowSeconds: 300
  #     policies:
  #       - type: Percent
  #         value: 50
  #         periodSeconds: 60
  #   scaleUp:
  #     stabilizationWindowSeconds: 0
  #     policies:
  #       - type: Percent
  #         value: 100
  #         periodSeconds: 15

# ---------------------------------------------------------
# Pod Disruption Budget
# ---------------------------------------------------------
podDisruptionBudget:
  # -- Enable PodDisruptionBudget
  enabled: false
  # -- Minimum available pods (number or percentage)
  minAvailable: ""
  # -- Maximum unavailable pods (number or percentage)
  maxUnavailable: ""

# ---------------------------------------------------------
# Prometheus Monitoring
# ---------------------------------------------------------
# Note: Tika Server does not natively expose Prometheus metrics.
# These resources are useful when a sidecar exporter (e.g., JMX exporter) is added.
serviceMonitor:
  # -- Enable ServiceMonitor (requires Prometheus Operator)
  enabled: false
  interval: 30s
  scrapeTimeout: 10s
  path: /metrics
  # -- Extra labels for the ServiceMonitor
  labels: {}

podMonitor:
  # -- Enable PodMonitor (requires Prometheus Operator)
  enabled: false
  interval: 30s
  scrapeTimeout: 10s
  # -- Extra labels for the PodMonitor
  labels: {}

# ---------------------------------------------------------
# Network Policy
# ---------------------------------------------------------
networkPolicy:
  # -- Enable NetworkPolicy
  enabled: false
  policyTypes:
    - Ingress
    - Egress
  # -- Restrict ingress to same namespace only
  namespaceIsolation: true
  namespaceLabel:
    key: "kubernetes.io/metadata.name"
  # -- Ingress rules
  ingress:
    # -- Allow ingress from ingress controllers
    ingressControllers: false
    ingressNamespace: "ingress-nginx"
    # -- Allow ingress from monitoring services
    monitoring: false
    monitoringNamespace: "monitoring"

# ---------------------------------------------------------
# Extra JARs Volume (tika-extras)
# ---------------------------------------------------------
tikaExtras:
  # -- Enable mounting extra JARs at /tika-extras/
  enabled: false
  # -- Volume type: "emptyDir", "pvc", or "hostPath"
  type: emptyDir
  emptyDir:
    sizeLimit: 1Gi
  pvc:
    storageClass: ""
    size: 2Gi
    accessModes:
      - ReadWriteOnce
    # -- Use an existing PVC instead of creating one
    existingClaim: ""

# ---------------------------------------------------------
# Extensibility
# ---------------------------------------------------------
# -- Extra environment variables for the Tika container
extraEnv: []
# Example:
#   - name: JAVA_OPTS
#     value: "-Xmx2g"
#   - name: MY_VAR
#     valueFrom:
#       secretKeyRef:
#         name: my-secret
#         key: my-key

# -- Extra volume mounts for the Tika container
extraVolumeMounts: []
# Example:
#   - name: custom-jars
#     mountPath: /tika-extras
#     readOnly: true

# -- Extra volumes for the pod
extraVolumes: []
# Example:
#   - name: custom-jars
#     configMap:
#       name: tika-extra-jars

# -- Init containers
initContainers: []
# Example:
#   - name: download-models
#     image: busybox:1.36
#     command: ['sh', '-c', 'wget -O /tika-extras/model.jar https://example.com/model.jar']
#     volumeMounts:
#       - name: tika-extras
#         mountPath: /tika-extras

# -- Sidecar containers
sidecars: []
# Example:
#   - name: jmx-exporter
#     image: bitnami/jmx-exporter:latest
#     ports:
#       - containerPort: 5556

# ---------------------------------------------------------
# Scheduling
# ---------------------------------------------------------
# -- Node selector
nodeSelector: {}
# -- Tolerations
tolerations: []
# -- Affinity rules
affinity: {}
# -- Topology spread constraints
topologySpreadConstraints: []
# Example:
#   - maxSkew: 1
#     topologyKey: kubernetes.io/hostname
#     whenUnsatisfiable: DoNotSchedule
#     labelSelector:
#       matchLabels:
#         app.kubernetes.io/name: tika
```

### 7.4 Template Helpers (`_helpers.tpl`)

```text
Helpers to define:

tika.name              — chart name (truncated to 63 chars)
tika.fullname          — release-qualified name
tika.chart             — chart name + version (for labels)
tika.labels            — standard Kubernetes labels
tika.selectorLabels    — selector labels (name + instance)
tika.serviceAccountName — service account name resolution
tika.imageTag          — resolves image tag: explicit tag > appVersion-full > appVersion
```

Key helper — `tika.imageTag`:

```
{{- define "tika.imageTag" -}}
{{- if .Values.image.tag -}}
  {{- .Values.image.tag -}}
{{- else if .Values.tika.fullImage -}}
  {{- printf "%s-full" .Chart.AppVersion -}}
{{- else -}}
  {{- .Chart.AppVersion -}}
{{- end -}}
{{- end -}}
```

This automatically selects the full or minimal image based on the `tika.fullImage`
toggle, while allowing explicit override via `image.tag`.

### 7.5 Template Logic — Conditional Resources

| Template | Created When |
|----------|-------------|
| `deployment.yaml` | Always |
| `service.yaml` | `service.enabled` |
| `serviceaccount.yaml` | `serviceAccount.create` |
| `configmap.yaml` | `tika.config` or `tika.additionalConfigs` |
| `ingress.yaml` | `ingress.enabled` |
| `hpa.yaml` | `autoscaling.enabled` |
| `poddisruptionbudget.yaml` | `podDisruptionBudget.enabled` |
| `servicemonitor.yaml` | `serviceMonitor.enabled` and `service.enabled` |
| `podmonitor.yaml` | `podMonitor.enabled` |
| `networkpolicy.yaml` | `networkPolicy.enabled` |

### 7.6 Deployment Template — Key Design Decisions

#### Writable `/tmp` Volume

The Tika Docker image has `readOnlyRootFilesystem: true` in the upstream chart
with a hardcoded `sec-ctx-vol` emptyDir mount at `/tmp`. We will keep
`readOnlyRootFilesystem: true` as default but implement the `/tmp` mount cleanly:

```yaml
volumes:
  - name: tmp
    emptyDir: {}
volumeMounts:
  - name: tmp
    mountPath: /tmp
```

#### ConfigMap Mount

When `tika.config` is set, the ConfigMap is mounted at `/tika-config/` and the
Tika container args include `-c /tika-config/tika-config.xml`:

```yaml
{{- if .Values.tika.config }}
args: ["-c", "/tika-config/tika-config.xml"]
{{- end }}
volumes:
  - name: tika-config
    configMap:
      name: {{ include "tika.fullname" . }}-config
volumeMounts:
  - name: tika-config
    mountPath: /tika-config
    readOnly: true
```

#### Extra JARs Mount

When `tikaExtras.enabled` is true:

```yaml
volumes:
  - name: tika-extras
    {{- if eq .Values.tikaExtras.type "pvc" }}
    persistentVolumeClaim:
      claimName: {{ .Values.tikaExtras.pvc.existingClaim | default (printf "%s-extras" (include "tika.fullname" .)) }}
    {{- else }}
    emptyDir:
      sizeLimit: {{ .Values.tikaExtras.emptyDir.sizeLimit }}
    {{- end }}
volumeMounts:
  - name: tika-extras
    mountPath: /tika-extras
```

#### JVM Options via Environment

When `tika.javaOpts` is set, it's injected as `JAVA_OPTS` env var. The
container entrypoint does not natively read `JAVA_OPTS`, so we handle this
by overriding the command to include the opts:

```yaml
{{- if .Values.tika.javaOpts }}
command:
  - /bin/sh
  - -c
  - >-
    exec java {{ .Values.tika.javaOpts }}
    -cp "/tika-server-standard-${TIKA_VERSION}.jar:/tika-extras/*"
    org.apache.tika.server.core.TikaServerCli -h 0.0.0.0
    {{- if .Values.tika.config }} -c /tika-config/tika-config.xml{{- end }}
    {{- if .Values.tika.cors }} --cors {{ .Values.tika.cors | quote }}{{- end }}
{{- end }}
```

#### Replicas vs Autoscaling

When autoscaling is enabled, `replicas` is omitted from the Deployment spec:

```yaml
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
```

### 7.7 NOTES.txt

```text
NOTES.txt will display:

1. How to get the application URL (port-forward, service URL, ingress URL).
2. How to test the connection:
   curl http://<service>:9998/version
3. Warning if using default resources (recommend tuning for production).
```

---

## 8. Repository & CI/CD Structure

### 8.1 Repository Layout

```text
helm-charts/
├── .github/
│   ├── cr.yaml                    # chart-releaser config
│   └── workflows/
│       ├── helm-lint-test.yml     # PR: lint + template + unittest
│       ├── helm-release.yml       # Push to master: package + release via chart-releaser
│       └── setup-pages.yml        # One-time: create gh-pages branch
├── charts/
│   └── tika/                      # The actual chart
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values.schema.json
│       ├── README.md
│       ├── .helmignore
│       ├── templates/
│       │   └── ...
│       └── tests/
│           └── ...
├── examples/                      # Reference examples (existing)
│   ├── github-actions/
│   └── helm-chart/
├── PLANNING-tika.md               # This document
├── PLANNING-docling.md            # Docling planning (existing)
└── README.md                      # Repo-level README
```

### 8.2 GitHub Actions — Lint & Test (`helm-lint-test.yml`)

Triggers on PRs touching `charts/tika/**`:

1. Checkout.
2. Setup Helm v3.14+.
3. `helm lint charts/tika`.
4. `helm template` with each CI values file in `charts/tika/tests/`.
5. (Optional) `helm-unittest` with the test suites.
6. (Optional) `ct lint` using chart-testing.

### 8.3 GitHub Actions — Release (`helm-release.yml`)

Triggers on push to `master` touching `charts/tika/**`:

1. Checkout with full history.
2. Setup Helm.
3. Configure Git identity.
4. Run `helm/chart-releaser-action@v1.7.0`:
   - `charts_dir: charts`
   - `config: .github/cr.yaml`
   - Publishes to GitHub Releases + updates `gh-pages` index.

### 8.4 `cr.yaml` (Chart Releaser Config)

```yaml
owner: kenchrcum
repo: helm-charts
charts-repo-url: https://kenchrcum.github.io/helm-charts
pages-branch: gh-pages
pages-index-path: index.yaml
release-name-template: "{{ .Name }}-{{ .Version }}"
```

### 8.5 Helm Repository Usage

After release, users consume the chart via:

```sh
helm repo add kenchrcum https://kenchrcum.github.io/helm-charts
helm repo update
helm install tika kenchrcum/tika
```

Or with custom values:

```sh
helm install tika kenchrcum/tika \
  --namespace default \
  --set tika.fullImage=true
```

Then verify the deployment:

```sh
kubectl port-forward svc/tika 9998:9998
curl http://localhost:9998/version
```

---

## 9. Implementation Phases

### Phase 1 — Skeleton & Basic Deployment (MVP)

**Goal:** Deployable chart with a working Tika Server, basic probes, and service.

**Tasks:**

- [ ] Create `charts/tika/Chart.yaml`
- [ ] Create `charts/tika/values.yaml` (full structure, sensible defaults)
- [ ] Create `charts/tika/.helmignore`
- [ ] Create `templates/_helpers.tpl` (all helper functions including `tika.imageTag`)
- [ ] Create `templates/deployment.yaml` (with `/tmp` emptyDir, probe support, resource management)
- [ ] Create `templates/service.yaml`
- [ ] Create `templates/serviceaccount.yaml`
- [ ] Create `templates/NOTES.txt` (with deployment verification steps)
- [ ] Create `templates/tests/test-connection.yaml`
- [ ] Validate with `helm lint` and `helm template`

**Deliverable:** `helm install tika charts/tika` deploys a working Tika Server.

### Phase 2 — Configuration & ConfigMap

**Goal:** Full support for custom Tika configuration, extra JARs, and JVM options.

**Tasks:**

- [ ] Create `templates/configmap.yaml` (tika-config.xml + additionalConfigs)
- [ ] Update `deployment.yaml` to conditionally mount ConfigMap and pass `-c` flag
- [ ] Implement `tika.javaOpts` command override logic
- [ ] Implement `tika.cors` flag support
- [ ] Implement `tikaExtras` volume mount
- [ ] Add `extraEnv`, `extraVolumes`, `extraVolumeMounts` support
- [ ] Add `initContainers` and `sidecars` support
- [ ] Test with custom config values

**Deliverable:** Full configuration flexibility for Tika Server.

### Phase 3 — Production Features

**Goal:** Production-readiness with ingress, scaling, monitoring, and security.

**Tasks:**

- [ ] Create `templates/ingress.yaml` (with proper `ingressClassName`, path types)
- [ ] Create `templates/hpa.yaml` (with autoscaling behavior policies)
- [ ] Create `templates/poddisruptionbudget.yaml`
- [ ] Create `templates/servicemonitor.yaml`
- [ ] Create `templates/podmonitor.yaml`
- [ ] Create `templates/networkpolicy.yaml` (with namespace isolation, DNS egress)
- [ ] Create `values.schema.json` for input validation
- [ ] Review and harden security defaults

**Deliverable:** Full-featured chart with all production knobs.

### Phase 4 — CI/CD, Testing & Documentation

**Goal:** Automated testing and publishing pipeline.

**Tasks:**

- [ ] Create `.github/cr.yaml`
- [ ] Create `.github/workflows/helm-lint-test.yml`
- [ ] Create `.github/workflows/helm-release.yml`
- [ ] Create `.github/workflows/setup-pages.yml` (if not already present)
- [ ] Create CI values files (`tests/ci-default.yaml`, `ci-custom-config.yaml`, `ci-full-features.yaml`, `ci-minimal-image.yaml`)
- [ ] Write comprehensive `charts/tika/README.md` with usage examples
- [ ] Write `charts/tika/scripts/test-chart.sh` for local testing
- [ ] Test full release flow

**Deliverable:** Automated chart releases to `https://kenchrcum.github.io/helm-charts`.

### Phase 5 — Polish & Community

**Goal:** Documentation, examples, and community-ready publication.

**Tasks:**

- [ ] Add example values for common scenarios:
  - `examples/basic-deployment.yaml` — minimal Tika with default full image
  - `examples/custom-ocr.yaml` — custom OCR configuration
  - `examples/minimal-image.yaml` — using the smaller non-OCR image
  - `examples/high-availability.yaml` — multi-replica with HPA and PDB
- [ ] Repo-level `README.md` with badges, quick-start, architecture diagram
- [ ] Security review (no secrets in plain text, proper RBAC)
- [ ] Consider Artifact Hub registration via annotations in Chart.yaml
- [ ] Document upgrade path from upstream apache/tika-helm chart

---

## 10. Testing Strategy

### 10.1 Static Analysis

| Tool | What it checks |
|------|----------------|
| `helm lint` | Chart structure, YAML validity, common errors |
| `helm template` | Renders all templates without a cluster |
| `ct lint` (chart-testing) | Additional linting (version bump check, README) |
| `values.schema.json` | Validates user-provided values against JSON Schema |

### 10.2 Unit Tests (helm-unittest)

Test suites for each template, covering:

- **Default values** — chart renders without errors; full image tag selected.
- **Minimal image** — `tika.fullImage=false` produces tag without `-full` suffix.
- **Explicit tag** — `image.tag` overrides auto-detection.
- **Custom config** — ConfigMap created; deployment mounts it; `-c` flag present.
- **Additional configs** — extra files appear in ConfigMap.
- **JVM options** — command override includes `JAVA_OPTS`.
- **CORS** — `--cors` flag present in args.
- **Extra JARs** — `tikaExtras` volume mount appears.
- **Ingress enabled** — ingress resource created with correct hosts/TLS/className.
- **Autoscaling** — HPA created; `replicas` not set on Deployment.
- **PDB** — created with correct minAvailable/maxUnavailable.
- **ServiceMonitor** — created with correct labels and endpoints.
- **PodMonitor** — created with correct labels.
- **NetworkPolicy** — created with namespace isolation and DNS egress.
- **Service disabled** — no Service resource when `service.enabled=false`.
- **Extra env/volumes** — injected correctly into deployment.
- **Init containers / sidecars** — appear in pod spec.
- **Security context** — defaults enforce non-root, no privilege escalation, seccomp.

### 10.3 CI Values Files

| File | Scenario |
|------|----------|
| `ci-default.yaml` | Default deployment (full image, no custom config) |
| `ci-minimal-image.yaml` | Minimal image (`tika.fullImage=false`) |
| `ci-custom-config.yaml` | Custom tika-config.xml with OCR settings |
| `ci-full-features.yaml` | Everything enabled (ingress, HPA, PDB, monitoring, network policy, extras) |

### 10.4 Integration Tests

- `templates/tests/test-connection.yaml`: Helm test pod that curls `/version` endpoint and validates response.
- Future: kind-based integration test in CI (spin up a cluster, install chart, run `helm test`, submit a test document).

### 10.5 Local Testing Script

`charts/tika/scripts/test-chart.sh`:

```sh
#!/bin/bash
set -euo pipefail

# Test 1: Default configuration
helm template test . > /dev/null
echo "✓ Default template renders"

# Test 2: Minimal image
helm template test . --set tika.fullImage=false > /dev/null
echo "✓ Minimal image template renders"

# Test 3: Custom config
helm template test . --set tika.config="<properties></properties>" > /dev/null
echo "✓ Custom config template renders"

# Test 4: Full features
helm template test . -f tests/ci-full-features.yaml > /dev/null
echo "✓ Full features template renders"

# Test 5: Helm lint
helm lint . > /dev/null 2>&1
echo "✓ Chart passes linting"
```

---

## 11. Open Questions & Decisions

| # | Question | Decision | Rationale |
|---|----------|----------|-----------|
| 1 | Default image: full or minimal? | **Full** (`3.3.0-full`) | The full image includes Tesseract OCR and language packs for comprehensive document extraction. Users can override to minimal variant if needed. |
| 2 | `readOnlyRootFilesystem`? | **`true`** with `/tmp` emptyDir | Tika only needs writable `/tmp` for processing. The upstream chart already does this (albeit clumsily). Clean emptyDir mount is more secure. |
| 3 | `allowPrivilegeEscalation`? | **`false`** | The upstream chart defaults to `true` which is unnecessarily permissive. Tika runs as UID 35002 and has no need for privilege escalation. |
| 4 | Health check endpoint? | **`GET /version`** | Returns a simple text response (`Apache Tika 3.x.x.x`). More reliable than `GET /` which returns HTML. Lightweight and fast. |
| 5 | Startup probe? | **Yes** — critical | JVM startup takes 10-30 seconds. Without a startup probe, the liveness probe may kill pods before they're ready. Allow up to 120s for startup. |
| 6 | Default resource requests? | **500m CPU / 1Gi RAM request; 2 CPU / 2Gi RAM limit** | Tika is memory-hungry, especially with OCR. The full image needs ~1.5GB under load. These are conservative but usable defaults. |
| 7 | Chart versioning vs appVersion? | **Independent** | Chart version tracks our chart changes. `appVersion` tracks the upstream Tika version. The `tika.fullImage` toggle handles the `-full` suffix automatically. |
| 8 | Prometheus metrics? | **ServiceMonitor/PodMonitor templates included but disabled** | Tika Server does not natively export Prometheus metrics. The templates are there for users who add a JMX exporter sidecar. |
| 9 | Support companion services (Grobid, Vision, NER)? | **Out of scope** | Each requires its own image, config, and deployment. Document as advanced pattern using `tika.config` to point to external services. |
| 10 | Named port? | **`http` on 9998** | Consistent with Helm conventions. Used by probes and service targeting. |
| 11 | `namespaceOverride` support? | **No** — use `--namespace` flag | The upstream chart supports this but it's an anti-pattern. Helm's `--namespace` is the standard way. Simplifies templates. |
| 12 | Naming convention: `tika` vs `tika-helm`? | **`tika`** | Cleaner. The upstream uses `tika-helm` for internal template names but `tika` as the chart name. We use `tika` consistently. |
| 13 | Writable `/tika-config` mount? | **`readOnly: true`** | Config files should never be modified at runtime. Mount as read-only for security. |
| 14 | Default HPA max replicas? | **10** (not 100 as in upstream) | 100 replicas of a 2GB-memory pod is unrealistic. 10 is a more sensible default that won't accidentally blow up a cluster. |