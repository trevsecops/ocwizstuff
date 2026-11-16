# Wiz on OpenShift (on-prem)

Deploys the Wiz **Runtime Sensor** and the **Kubernetes Connector with Broker** to the on-premise OpenShift clusters, from GitLab CI, with the unified Helm chart `wiz-sec/wiz-kubernetes-integration`. The Admission Controller is switched off and can be enabled later with one value.

Owned by the Cloud Security Team. The platform team operates the clusters and approves changes under `helm/` and `manifests/`.

> **Status: staged.** Every environment-specific value is a `<PLACEHOLDER>`. The deploy job refuses to run for a cluster while any placeholder remains in the files that cluster uses.

## Tenant facts used in this repo

| Item | Value |
|---|---|
| Wiz edition | Commercial (app.wiz.io) |
| Data center | us44 |
| Region | us-west-2 (DR us-east-2) |
| Auth URL | https://auth.app.wiz.io/oauth/token |
| Namespace | `wiz` |
| Helm release | `wiz-integration` |
| Chart pin | `wiz-kubernetes-integration` 0.3.94 (wiz-sensor 1.0.13112, wiz-kubernetes-connector 4.0.9, wiz-broker 3.0.6) |

## Layout

```
.gitlab-ci.yml                      pipeline: validate, render, mirror, deploy, verify
helm/values/base.yaml               values shared by every cluster
helm/values/clusters/_template.yaml copy per cluster
helm/values/clusters/<cluster>.yaml one file per cluster (nonprod-example.yaml is a sample)
helm/values/optional/               overlays switched on per cluster with EXTRA_VALUES
  pull-secret.yaml                    internal registry needs credentials
  proxy.yaml                          egress through an HTTP(S) proxy
  static-ip.yaml                      firewall allows IPs only
  workload-scanner.yaml               Sensor-based Workload Scanner
images/images.txt                   Broker image to mirror (Sensor is mirrored elsewhere)
manifests/namespace.yaml            the wiz project
manifests/external-secrets/         ExternalSecret that syncs the Wiz service account from CyberArk
  wiz-api-token.yaml                  default for every cluster
  clusters/<cluster>.yaml             optional per-cluster copy, used instead of the default
  examples/                           reference SecretStore for the Conjur provider (not applied)
scripts/                            render, mirror, secrets, deploy, validate
docs/RUNBOOK.md                     step-by-step rollout, upgrade, rollback, troubleshooting
docs/NETWORK-EGRESS.md              firewall request for us44
```

## Placeholders to replace in Git

| Placeholder | File | What to put there |
|---|---|---|
| `<SENSOR_IMAGE_REGISTRY>` | `helm/values/base.yaml` | Registry host and path prefix of the **existing** internal Sensor mirror. Also check `repository` (default `sensor`) and `tag` (default `v1`) on the next two lines against what that mirror really holds |
| `<PRIVATE_REGISTRY>` | `helm/values/base.yaml` (2 places) | Internal registry host and optional path prefix for the Broker image, for example `registry.example.internal/wiz`. Can be the same registry as the Sensor |
| `<SECRET_STORE_NAME>` | `manifests/external-secrets/wiz-api-token.yaml` | Name of the existing CyberArk `ClusterSecretStore` on the clusters. Change `kind` to `SecretStore` if it is namespaced |
| `<CYBERARK_CLIENT_ID_KEY>` | `manifests/external-secrets/wiz-api-token.yaml` | CyberArk path of the Wiz service account Client ID |
| `<CYBERARK_CLIENT_SECRET_KEY>` | `manifests/external-secrets/wiz-api-token.yaml` | CyberArk path of the Wiz service account Client Secret |
| `<CLUSTER_NAME>` | `helm/values/clusters/<cluster>.yaml` | Name shown in Wiz for this cluster |
| `<CONNECTOR_NAME>` | `helm/values/clusters/<cluster>.yaml` | Connector name in Wiz. Use a clear and unique name per cluster |
| `<ENVIRONMENT>` | `helm/values/clusters/<cluster>.yaml` | Cluster tag value such as `nonprod` or `prod` |
| `<CI_TOOLS_IMAGE>` | `.gitlab-ci.yml` | Internal CI image with bash, helm 3.11 or later, oc, skopeo, yamllint and shellcheck |
| `<RUNNER_TAG>` | `.gitlab-ci.yml` | Tag of the runners that can reach the clusters and the internal registry |
| `<CLOUD_SECURITY_GROUP>`, `<PLATFORM_GROUP>` | `CODEOWNERS` | GitLab group paths |

Also rename `nonprod-example.yaml` to the real cluster name and update the `CLUSTER` matrix in `.gitlab-ci.yml`.

## CI/CD variables to create in GitLab (never in Git)

| Variable | Scope | Flags | Purpose |
|---|---|---|---|
| `OPENSHIFT_API_URL` | environment `openshift/<cluster>` | protected | API server URL of that cluster |
| `OPENSHIFT_TOKEN` | environment `openshift/<cluster>` | masked, protected | Token of the deployer ServiceAccount on that cluster |
| `OPENSHIFT_CA_FILE` | environment `openshift/<cluster>` | File type, optional | API server CA bundle when it is not publicly trusted |
| `EXTRA_VALUES` | environment `openshift/<cluster>` | optional | Space-separated overlays, for example `proxy pull-secret` |
| `PRIVATE_REGISTRY` | project | optional | Same value as the placeholder. Needed by the mirror job and the pull-secret overlay |
| `PRIVATE_REGISTRY_USERNAME`, `PRIVATE_REGISTRY_PASSWORD` | project | masked, protected, optional | Push credentials for the Broker mirror job. Also used for the pull secret overlay |
| `MIRROR_IMAGES` | pipeline schedule | optional | Set to `true` on a schedule to refresh the Broker image |
| `SECRETS_MODE` | environment, optional | | Leave unset. Default `external` uses CyberArk. `ci` is a fallback that reads `WIZ_CLIENT_ID` and `WIZ_CLIENT_SECRET` from masked and protected CI variables |

**The Wiz service account credential is not a GitLab variable.** It lives in CyberArk and reaches the cluster through the External Secrets Operator.

Protected variables are only exposed on protected branches, so deploys run from the default branch only. Mark the `openshift/*` production environments as protected environments and restrict who can run the manual deploy job.

## Which secrets are needed

| Secret | Needed | Why |
|---|---|---|
| `wiz-api-token` (clientId, clientToken) | **Always** | This is how the Sensor, Connector and Broker authenticate to the Wiz tenant. Stored in CyberArk. An `ExternalSecret` creates the Kubernetes Secret with these two exact key names |
| Wiz registry pull key (`wizio.azurecr.io`) | **Not used by this repo** | The Sensor image is already mirrored internally by an existing process. Nothing here pulls from the Wiz registry |
| Internal registry pull secret | Only if the internal registry requires authentication and the cluster global pull secret does not already cover it | Enable the `pull-secret` overlay in that case |

`base.yaml` therefore sets `wiz-sensor.imagePullSecret.required: false`.

## Pipeline

| Job | When | What it does |
|---|---|---|
| `lint` | every MR and default branch | yamllint, shellcheck, placeholder report |
| `render` | every MR and default branch | `helm template` per cluster. Publishes the manifests and the image list. Fails if any image still points at a Wiz registry or if a client token is rendered |
| `mirror-images` | manual or scheduled, optional | Copies the Broker image in `images/images.txt` into the internal registry with skopeo. The Sensor image is out of scope |
| `deploy` | manual, default branch | Placeholder gate, namespace, apply the `ExternalSecret` and wait for the CyberArk sync, `helm upgrade --install --wait`, then validation |
| `verify` | manual, default branch | Re-runs the read-only validation |

## First rollout in short

1. Store the Wiz service account in CyberArk and confirm the External Secrets Operator and its CyberArk store exist on the cluster.
1. Replace the placeholders and create the CI/CD variables.
2. Open a merge request. Review the `render` artifacts and confirm the image list.
3. Confirm the Sensor image reference in the `render` output matches the existing internal mirror. Make sure the Broker image exists in the internal registry and run `mirror-images` if it does not.
4. Confirm the egress in `docs/NETWORK-EGRESS.md` is open from the cluster.
5. Merge, then run `deploy` for one non-production cluster.
6. Confirm in the Wiz portal under Settings > Deployments.

Details, rollback and troubleshooting are in `docs/RUNBOOK.md`.

## Deviations from the OpenShift Deployment Guide v1.0

These were found by reading the chart source for the pinned versions. Confirm each one in the first `render` job output.

1. **Registry override is set per component, not with `global.image.registry`.** The Broker image helper resolves to `<registry>/wiz-broker` when the global key is used, which drops the `wiz-app/` path segment. The Sensor resolves to `<registry>/sensor`. Per-component `image.registry` values, as in the Wiz private registry example, keep both source paths intact.
2. **The Sensor ignores `global.imagePullSecrets` while `imagePullSecret.required` is `false`.** The guide combines the two. If the internal registry needs credentials the Sensor pods would get no pull secret. The `pull-secret` overlay sets `required: true` with the existing secret name.
3. **Admission Controller is disabled** by decision for this phase.
4. **Chart version is pinned** and the rendered image list is reviewed on every change, because the Sensor image uses the floating tag `v1`.
5. **The Sensor image is not mirrored by this repo.** It is consumed from the existing internal mirror, so the guide step that logs in to `wizio.azurecr.io` does not apply here.
