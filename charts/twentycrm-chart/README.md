# Twenty CRM - Helm chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/twentycrm)](https://artifacthub.io/packages/search?repo=twentycrm)
[![Release](https://img.shields.io/github/v/tag/Kaiwhodevs/twentycrm-chart?label=chart&sort=semver)](https://github.com/Kaiwhodevs/twentycrm-chart/tags)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](https://github.com/Kaiwhodevs/twentycrm-chart/blob/main/LICENSE)
[![Signed with cosign](https://img.shields.io/badge/signed-cosign-2f7de1.svg)](#security--supply-chain)

A production-ready Helm chart for [**Twenty CRM**](https://github.com/twentyhq/twenty),
packaged for Kubernetes and distributed via **OCI on GHCR**.

It mirrors the official
[`twenty-docker` compose file](https://raw.githubusercontent.com/twentyhq/twenty/main/packages/twenty-docker/docker-compose.yml)
exactly - same services, same defaults, same environment variables - so a default
install behaves like `docker compose up`, just on Kubernetes.

```text
Registry:  oci://ghcr.io/kaiwhodevs/twentycrm-chart
Artifact Hub:  https://artifacthub.io/packages/helm/twentycrm/twentycrm-chart
```

---

## Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quickstart](#quickstart)
- [Production usage](#production-usage)
  - [Use an existing Secret](#use-an-existing-secret)
  - [External database / Redis](#external-database--redis)
  - [Email, OAuth & other integrations](#email-oauth--other-integrations)
  - [File storage](#file-storage)
- [Upgrades](#upgrades)
- [Uninstall](#uninstall)
- [Configuration reference](#configuration-reference)
- [Security & supply chain](#security--supply-chain)
- [How it works](#how-it-works)
- [Releases & automation](#releases--automation)
- [License](#license)

---

## Overview

| Compose service | Kubernetes resources | Image |
| --------------- | -------------------- | ----- |
| `server` | Deployment + Service (port 3000) | `twentycrm/twenty` |
| `worker` | Deployment (`yarn worker:prod`) | `twentycrm/twenty` |
| `db` | StatefulSet + Service | `postgres:16` |
| `redis` | Deployment + Service | `redis` |

**Highlights**

- **Faithful to the docker install** - bundled `postgres:16` and `redis` with the
  same defaults and env vars as the compose file (no opinionated subcharts).
- **Secrets done right** - sensitive values go to a **Secret** (auto-generated or
  bring-your-own via `secret.secretRef`); everything else to a **ConfigMap**.
- **Version locked to upstream** - the chart version equals the Twenty release it
  deploys (`v`-prefixed, e.g. `v2.8.3`), kept in sync automatically.
- **Standard conventions** - `global.*`, `commonLabels/Annotations`, HPA, PDB,
  probes, `helm test`, `values.schema.json`, and a **cosign-signed** artifact.

---

## Prerequisites

- Kubernetes **1.23+**
- Helm **3.8+** (OCI support, enabled by default)
- A default `StorageClass` (or set `*.persistence.storageClass`)
- A way to reach the `server` Service - Ingress, `LoadBalancer`, or `port-forward`

---

## Quickstart

Install straight from GHCR - no `helm repo add` needed. `APP_SECRET` and
`ENCRYPTION_KEY` are auto-generated on first install and preserved across upgrades,
so a default install just works:

```bash
helm install twenty oci://ghcr.io/kaiwhodevs/twentycrm-chart \
  --version v2.8.3 \
  --set config.serverUrl=https://crm.example.com
```

Verify the deployment and open the app:

```bash
helm test twenty                                              # probes /healthz
kubectl port-forward svc/twenty-twentycrm-chart-server 3000:3000
# open http://localhost:3000
```

> [!NOTE]
> The default install bundles PostgreSQL and Redis with the compose defaults
> (`postgres`/`postgres`, database `default`). Fine for a trial - but for
> production, **set a real DB password and manage secrets yourself** (below).

---

## Production usage

### Secret-free values (`secretRef` + `secretRefKey`)

For production, keep **every** secret out of your values and Helm release history.
Each component that needs secrets supports two fields:

- `secretRef` - the name of a pre-created Kubernetes Secret.
- `secretRefKey` - a map of `<field>: <key-in-that-secret>` (keys default to the
  env-var name, so you only set this if your Secret uses different key names).

When `secretRef` is set, the chart sources those values via `secretKeyRef` and
generates **no** Secret - nothing sensitive ever touches `values.yaml`.

**1. Create the Secrets yourself** (sealed-secrets, External Secrets Operator,
`kubectl`, …):

```bash
# DB password (consumed by the bundled Postgres as POSTGRES_PASSWORD)
kubectl create secret generic cod3labs-twenty-db \
  --from-literal=PG_DATABASE_PASSWORD="$(openssl rand -base64 24)"

# App secrets + the full connection string (consumed by server & worker)
kubectl create secret generic cod3labs-twenty-secret \
  --from-literal=APP_SECRET="$(openssl rand -base64 32)" \
  --from-literal=ENCRYPTION_KEY="$(openssl rand -base64 32)" \
  --from-literal=FALLBACK_ENCRYPTION_KEY="" \
  --from-literal=PG_DATABASE_URL="postgres://postgres:THE_SAME_DB_PASSWORD@twenty-twentycrm-chart-db:5432/default"
```

**2. Point the chart at them** - this values file contains no secrets at all
(see [`examples/secret-free.yaml`](examples/secret-free.yaml)):

```yaml
postgresql:
  auth:
    secretRef: cod3labs-twenty-db
    secretRefKey:
      password: PG_DATABASE_PASSWORD

secret:
  secretRef: cod3labs-twenty-secret
  secretRefKey:
    appSecret: APP_SECRET
    encryptionKey: ENCRYPTION_KEY
    fallbackEncryptionKey: FALLBACK_ENCRYPTION_KEY
    pgDatabaseUrl: PG_DATABASE_URL
```

> The password inside `PG_DATABASE_URL` must equal the `PG_DATABASE_PASSWORD` in
> the DB Secret, and the host should be `<release>-twentycrm-chart-db` (or your
> external database). The two `secretRef`s may point at the same Secret if you
> prefer - just put all keys in one.

A complete production values file (S3 storage, ingress + TLS, HA server,
autoscaling, PDB) using this pattern is in
[`examples/production.yaml`](examples/production.yaml):

```bash
helm install twenty oci://ghcr.io/kaiwhodevs/twentycrm-chart \
  --version v2.8.3 -f examples/production.yaml
```

### External database / Redis

Point at managed services instead of the bundled ones (full file:
[`examples/external-services.yaml`](examples/external-services.yaml)):

```yaml
postgresql:
  enabled: false
externalDatabase:
  url: postgres://user:password@my-postgres-host:5432/default

redis:
  enabled: false
externalRedis:
  url: redis://my-redis-host:6379
```

> When the chart generates the Secret, `externalDatabase.url` is written to
> `PG_DATABASE_URL`. With `secret.secretRef`, set `PG_DATABASE_URL` in that Secret.

### Email, OAuth & other integrations

Optional integrations from the upstream compose go through two escape hatches -
non-sensitive vars into the ConfigMap, secrets into the Secret:

```yaml
extraEnv:                        # -> ConfigMap
  EMAIL_FROM_ADDRESS: contact@example.com
  EMAIL_DRIVER: smtp
  EMAIL_SMTP_HOST: smtp.example.com
  EMAIL_SMTP_PORT: "465"
secret:
  extraEnv:                      # -> Secret
    EMAIL_SMTP_PASSWORD: "..."
    AUTH_GOOGLE_CLIENT_SECRET: "..."
```

With `secret.secretRef`, add the sensitive keys to your own Secret instead.

### File storage

With the default `STORAGE_TYPE=local`, the `server` and `worker` pods share one
`ReadWriteOnce` PVC (mirroring the compose `server-local-data` volume). To make
this work on **any** cluster out of the box, the worker is scheduled onto the
**same node** as the server (a pod affinity), so the RWO volume mounts fine on
single- and multi-node clusters alike - no `ReadWriteMany` required.

You only need to change this if you want to **scale the server beyond one
replica** (the RWO volume can't span nodes). In that case either:

- set `localStorage.persistence.accessModes: [ReadWriteMany]` with an RWX storage
  class (e.g. Longhorn, NFS, CephFS), or
- **(recommended)** switch to S3 object storage (`config.storage.type=s3`) and set
  `localStorage.persistence.enabled=false` - then the pods share nothing and can
  schedule freely.

(The co-location affinity is skipped automatically when `localStorage.persistence`
is disabled, and can be overridden any time via `worker.affinity`.)

---

## Upgrades

The chart version equals the Twenty release it deploys, so upgrading the chart
upgrades Twenty.

```bash
helm show chart oci://ghcr.io/kaiwhodevs/twentycrm-chart --version v2.8.3   # inspect
helm upgrade twenty oci://ghcr.io/kaiwhodevs/twentycrm-chart \
  --version v2.8.3 -f examples/production.yaml
```

- **Migrations** run on the server at startup (`DISABLE_DB_MIGRATIONS` empty there,
  forced `"true"` on the worker - exactly as in the compose). **Back up the DB**
  before a major upgrade.
- **Pin** `--version` to an exact `vX.Y.Z` in production; review the
  [upstream release notes](https://github.com/twentyhq/twenty/releases).
- Server/worker default to the **`Recreate`** strategy (they share an RWO volume, so
  a rolling update would deadlock). For zero-downtime upgrades use S3/RWX storage and
  set `server.strategy.type=RollingUpdate`.

---

## Uninstall

```bash
helm uninstall twenty
```

> The local-storage PVC is annotated `helm.sh/resource-policy: keep`, so uploaded
> files survive an uninstall. Delete the PVC manually if you want the data gone.

---

## Configuration reference

| Key | Default | Description |
| --- | ------- | ----------- |
| `global.imageRegistry` | `""` | Override registry for all images |
| `global.imagePullSecrets` | `[]` | Pull secrets for all pods |
| `global.storageClass` | `""` | Default StorageClass for all PVCs |
| `commonLabels` / `commonAnnotations` | `{}` | Added to every object |
| `clusterDomain` | `cluster.local` | DNS domain for service hostnames |
| `nameOverride` / `fullnameOverride` / `namespaceOverride` | `""` | Name/namespace overrides |
| `extraDeploy` | `[]` | Extra raw manifests (templated) to deploy |
| `serviceAccount.create` / `.name` / `.automount` | `true` / `""` / `true` | ServiceAccount settings |
| `image.registry` / `.repository` | `""` / `twentycrm/twenty` | Server/worker image |
| `image.tag` | `v2.8.3` | Image tag (falls back to `.Chart.AppVersion`) |
| `config.serverUrl` | `""` | `SERVER_URL` - public URL of the instance |
| `config.nodePort` | `3000` | `NODE_PORT` |
| `config.disableDbMigrations` | `""` | `DISABLE_DB_MIGRATIONS` (server) |
| `config.disableCronJobsRegistration` | `""` | `DISABLE_CRON_JOBS_REGISTRATION` (server) |
| `config.storage.type` | `""` | `STORAGE_TYPE` (`""` = local, `s3`) |
| `config.storage.s3Region` / `s3Name` / `s3Endpoint` | `""` | S3 storage settings |
| `extraEnv` | `{}` | Extra non-sensitive env → ConfigMap |
| `secret.secretRef` | `""` | Pre-created Secret for APP_SECRET/ENCRYPTION_KEY/FALLBACK_ENCRYPTION_KEY/PG_DATABASE_URL (secret-free values) |
| `secret.secretRefKey` | `{}` | Map of `field: keyInSecret` (defaults to the env-var name) |
| `secret.appSecret` | `""` | `APP_SECRET`, generated mode (auto-generated when empty) |
| `secret.encryptionKey` | `""` | `ENCRYPTION_KEY`, generated mode (auto-generated when empty) |
| `secret.fallbackEncryptionKey` | `""` | `FALLBACK_ENCRYPTION_KEY`, generated mode |
| `secret.extraEnv` | `{}` | Extra sensitive env → generated Secret |
| `server.replicaCount` | `1` | Server replicas (ignored when autoscaling) |
| `server.strategy` | `Recreate` | Update strategy (RWO volume → Recreate) |
| `server.service.type` / `.port` | `ClusterIP` / `3000` | Server Service |
| `server.startupProbe` | `/healthz`, ~5 min | Guards slow first-boot migrations |
| `server.livenessProbe` / `.readinessProbe` | `/healthz` | Probes (`.enabled=false` to disable) |
| `server.autoscaling.enabled` | `false` | HorizontalPodAutoscaler for the server |
| `server.pdb.enabled` | `false` | PodDisruptionBudget for the server |
| `server.resources` / `worker.resources` | `{}` | Resource requests/limits |
| `server.extraVolumes` / `.extraVolumeMounts` | `[]` | Extra volumes/mounts (also on `worker`) |
| `worker.replicaCount` | `1` | Worker replicas |
| `postgresql.enabled` | `true` | Deploy the bundled PostgreSQL |
| `postgresql.auth.username` / `.database` | `postgres` / `default` | DB user / database (non-sensitive) |
| `postgresql.auth.secretRef` | `""` | Pre-created Secret for the DB password (`POSTGRES_PASSWORD` via secretKeyRef) |
| `postgresql.auth.secretRefKey` | `{}` | Map `password: keyInSecret` (default `PG_DATABASE_PASSWORD`) |
| `postgresql.auth.password` | `postgres` | DB password, generated mode (used only when `secretRef` is empty) |
| `postgresql.persistence.*` | `8Gi`, RWO | DB volume |
| `externalDatabase.url` | `""` | External `PG_DATABASE_URL` |
| `redis.enabled` | `true` | Deploy the bundled Redis |
| `redis.maxmemoryPolicy` | `noeviction` | Redis `--maxmemory-policy` |
| `redis.persistence.enabled` | `false` | Persist Redis (becomes a StatefulSet) |
| `externalRedis.url` | `""` | External `REDIS_URL` |
| `localStorage.persistence.*` | `8Gi`, RWO | Shared `.local-storage` volume |
| `ingress.*` | disabled | Ingress for the server Service |

See [`values.yaml`](values.yaml) for the full, commented list.

---

## Security & supply chain

This chart earns Artifact Hub's quality badges:

- **Values Schema** - ships a [`values.schema.json`](values.schema.json) that
  validates your values on install/upgrade.
- **Signed** - every release is signed with [cosign](https://github.com/sigstore/cosign)
  (keyless, via GitHub Actions OIDC) and logged in the Rekor transparency log.

Verify a release before installing:

```bash
cosign verify ghcr.io/kaiwhodevs/twentycrm-chart:v2.8.3 \
  --certificate-identity-regexp '^https://github.com/Kaiwhodevs/twentycrm-chart/.github/workflows/release-chart.yml@.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

---

## How it works

- **Bundled DB/Redis are plain images.** `db` is `postgres:16`, `redis` is `redis` -
  the exact images and defaults from the compose, not Bitnami subcharts - so behavior
  matches `docker compose up`. Disable them (`postgresql.enabled=false`,
  `redis.enabled=false`) to use managed services.
- **Env split.** Non-sensitive vars render into a ConfigMap; sensitive ones into a
  Secret. The `server` runs migrations and cron; the `worker` forces
  `DISABLE_DB_MIGRATIONS`/`DISABLE_CRON_JOBS_REGISTRATION` to `"true"`.
- **Ordering.** Init-containers wait for the DB/Redis (and the worker waits for the
  server) before starting - mirroring the compose `depends_on` health gates.

---

## Releases & automation

Two GitHub Actions keep the chart in lockstep with upstream:

1. **`check-upstream-release.yml`** (every 6 h) - compares the latest
   `twentyhq/twenty` release to `Chart.yaml`. On a newer one it bumps `Chart.yaml` +
   `values.yaml`, commits, and pushes a matching `vX.Y.Z` tag.
2. **`release-chart.yml`** (on that tag) - lints, `helm package`s, `helm push`es to
   GHCR, and **cosign-signs** the artifact.

A third workflow, **`publish-artifacthub-metadata.yml`**, publishes
`artifacthub-repo.yml` to GHCR for the Verified Publisher badge.

> **One-time setup:** the bump workflow needs a repo secret **`RELEASE_PAT`** (a
> fine-grained PAT with `Contents: write`) so its tag push can trigger the release
> workflow - the default `GITHUB_TOKEN` can't trigger other workflows.

Cut a release manually any time:

```bash
git tag v2.8.3 && git push origin v2.8.3
```

---

## License

This chart (the packaging) is licensed under
[**Apache-2.0**](https://github.com/Kaiwhodevs/twentycrm-chart/blob/main/LICENSE).
Twenty CRM itself is developed by [twentyhq/twenty](https://github.com/twentyhq/twenty)
under its own license; this chart only references the upstream container images.
