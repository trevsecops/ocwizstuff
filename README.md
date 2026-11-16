# Wiz Runtime Sensor on OpenShift (on-prem)

Deploys the Wiz **Runtime Sensor** to the on-premise OpenShift clusters, from GitLab CI, with the Helm chart `wiz-sec/wiz-sensor`. Scope is the Sensor only. The Kubernetes Connector, Broker and Admission Controller are not part of this repo.

Owned by the Cloud Security Team. The platform team operates the clusters and approves changes under `helm/` and `manifests/`.

> **Status: staged.** Every environment-specific value is a `<PLACEHOLDER>`. The deploy job refuses to run for a cluster while any placeholder remains in the files that cluster uses.

## Design in four lines

- **Image:** already mirrored internally by an existing process. Nothing here pulls from the Wiz registry.
- **Credential:** the Wiz service account lives in CyberArk. The External Secrets Operator syncs it into the `wiz-api-token` Secret.
- **OpenShift:** `openshift: true` makes the chart create a dedicated SCC bound to the Sensor ServiceAccount.
- **Network:** outbound 443 only, from the nodes to four Wiz FQDNs.

## Tenant facts used in this repo

| Item | Value |
|---|---|
| Wiz edition | Commercial (app.wiz.io) |
| Data center | us44 |
| Region | us-west-2 (DR us-east-2) |
| Namespace | `wiz` |
| Helm release | `wiz-sensor` |
| Chart pin | `wiz-sensor` 1.0.13112 |

## Layout

```
.gitlab-ci.yml                      pipeline: validate, render, deploy, verify
helm/values/base.yaml               values shared by every cluster
helm/values/clusters/_template.yaml copy per cluster
helm/values/clusters/<cluster>.yaml one file per cluster (nonprod-example.yaml is a sample)
helm/values/optional/               overlays switched on per cluster with EXTRA_VALUES
  pull-secret.yaml                    internal registry needs credentials
  proxy.yaml                          egress through an HTTP(S) proxy
  static-ip.yaml                      firewall allows IPs only
  workload-scanner.yaml               Sensor-based Workload Scanner
manifests/namespace.yaml            the wiz project
manifests/external-secrets/         ExternalSecret that syncs the Wiz service account from CyberArk
  wiz-api-token.yaml                  default for every cluster
  clusters/<cluster>.yaml             optional per-cluster copy, used instead of the default
  examples/                           reference SecretStore for the Conjur provider (not applied)
scripts/                            render, secrets, deploy, validate
docs/RUNBOOK.md                     step-by-step rollout, upgrade, rollback, troubleshooting
docs/NETWORK-EGRESS.md              firewall request for us44
```

## Placeholders to replace in Git

| Placeholder | File | What to put there |
|---|---|---|
| `<SENSOR_IMAGE_REGISTRY>` | `helm/values/base.yaml` | Registry host and path prefix of the existing internal Sensor mirror. Also check `repository` (default `sensor`) and `tag` (default `v1`) on the next two lines against what that mirror really holds |
| `<SECRET_STORE_NAME>` | `manifests/external-secrets/wiz-api-token.yaml` | Name of the existing CyberArk `ClusterSecretStore` on the clusters. Change `kind` to `SecretStore` if it is namespaced |
| `<CYBERARK_CLIENT_ID_KEY>` | `manifests/external-secrets/wiz-api-token.yaml` | CyberArk path of the Wiz service account Client ID |
| `<CYBERARK_CLIENT_SECRET_KEY>` | `manifests/external-secrets/wiz-api-token.yaml` | CyberArk path of the Wiz service account Client Secret |
| `<CLUSTER_NAME>` | `helm/values/clusters/<cluster>.yaml` | Name shown in Wiz for this cluster |
| `<ENVIRONMENT>` | `helm/values/clusters/<cluster>.yaml` | Cluster tag value such as `nonprod` or `prod` |
| `<CI_TOOLS_IMAGE>` | `.gitlab-ci.yml` | Internal CI image with bash, helm 3.11 or later, oc, yamllint and shellcheck |
| `<RUNNER_TAG>` | `.gitlab-ci.yml` | Tag of the runners that can reach the cluster API servers |
| `<CLOUD_SECURITY_GROUP>`, `<PLATFORM_GROUP>` | `CODEOWNERS` | GitLab group paths |

Also rename `nonprod-example.yaml` to the real cluster name and update the `CLUSTER` matrix in `.gitlab-ci.yml`.

## CI/CD variables to create in GitLab
| Variable | Scope | Flags | Purpose |
|---|---|---|---|
| `OPENSHIFT_API_URL` | environment `openshift/<cluster>` | protected | API server URL of that cluster |
| `OPENSHIFT_TOKEN` | environment `openshift/<cluster>` | masked, protected | Token of the deployer ServiceAccount on that cluster |
| `OPENSHIFT_CA_FILE` | environment `openshift/<cluster>` | File type, optional | API server CA bundle when it is not publicly trusted |
| `EXTRA_VALUES` | environment `openshift/<cluster>` | optional | Space-separated overlays, for example `proxy pull-secret` |
| `PRIVATE_REGISTRY`, `PRIVATE_REGISTRY_USERNAME`, `PRIVATE_REGISTRY_PASSWORD` | project | masked, protected, optional | Only for the `pull-secret` overlay |
| `SECRETS_MODE` | environment, optional | | Leave unset. Default `external` uses CyberArk. `ci` is a fallback that reads `WIZ_CLIENT_ID` and `WIZ_CLIENT_SECRET` from masked and protected CI variables |

**The Wiz service account credential is not a GitLab variable.** It lives in CyberArk and reaches the cluster through the External Secrets Operator.

Protected variables are only exposed on protected branches, so deploys run from the default branch only.

## Which secrets are needed

| Secret | Needed | Why |
|---|---|---|
| `wiz-api-token` (clientId, clientToken) | **Always** | This is how the Sensor authenticates to the Wiz tenant. Stored in CyberArk. An `ExternalSecret` creates the Kubernetes Secret with these two exact key names. Service account type **Sensor** |
| Wiz registry pull key (`wizio.azurecr.io`) | **Not used by this repo** | The Sensor image is already mirrored internally by an existing process |
| Internal registry pull secret | Only if the internal registry requires authentication and the cluster global pull secret does not already cover it | Enable the `pull-secret` overlay in that case |

## Pipeline

| Job | When | What it does |
|---|---|---|
| `lint` | every MR and default branch | yamllint, shellcheck, placeholder report |
| `render` | every MR and default branch | `helm template` per cluster. Publishes the manifests and the image list. Fails if the image still points at a Wiz registry or if a client token is rendered |
| `deploy` | manual, default branch | Placeholder gate, namespace, apply the `ExternalSecret` and wait for the CyberArk sync, `helm upgrade --install --wait`, then validation |
| `verify` | manual, default branch | Re-runs the read-only validation |

## First rollout in short

1. Store the Wiz service account in CyberArk and confirm the External Secrets Operator and its CyberArk store exist on the cluster.
2. Replace the placeholders and create the CI/CD variables.
3. Open a merge request. Review the `render` artifacts and confirm the Sensor image reference matches the existing internal mirror.
4. Confirm the egress in `docs/NETWORK-EGRESS.md` is open from the cluster nodes.
5. Merge, then run `deploy` for one non-production cluster.
6. Confirm in the Wiz portal under Settings > Deployments > Sensors.

Details, rollback and troubleshooting are in `docs/RUNBOOK.md`.

## What Sensor-only means

- Runtime threat detection works for every pod and node the DaemonSet covers.
- Without a Kubernetes Connector, Wiz has no cluster inventory or configuration scanning for these clusters, and Sensor detections carry less cluster context. Wiz recommends pairing the Sensor with a Connector. It can be added later without changing the Sensor release.
- Vulnerability scanning of on-prem nodes needs the `workload-scanner` overlay.

## Deviations from the OpenShift Deployment Guide v1.0

1. **Scope is the Sensor only**, deployed with the standalone `wiz-sensor` chart. The guide installs four components with the unified chart. Release name is `wiz-sensor` and the SCC is `wiz-sensor-scc`.
2. **The Sensor image is not mirrored by this repo.** It is consumed from the existing internal mirror.
3. **The Sensor only attaches a pull secret when `imagePullSecret.required` is `true`.** The guide sets it to `false` while relying on a global pull secret, which would leave the Sensor without one. The `pull-secret` overlay sets it correctly.
4. **The credential comes from CyberArk** through an `ExternalSecret`, not from a manually created secret.
5. **Chart version is pinned** and the rendered image reference is reviewed on every change.
