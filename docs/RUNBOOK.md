# Runbook: Wiz Runtime Sensor on OpenShift

## 1. One-time prerequisites

**Wiz (Cloud Security Team)**

1. Create a service account of type **Sensor** under Settings > Access Management > Service Accounts. The Client Secret is shown once.
2. Store the Client ID and Client Secret in CyberArk straight from the Wiz dialog. Do not send them through chat or email and do not put them in GitLab.
3. Decide whether clusters share one service account or get one each. Rotating a secret invalidates the old one immediately, so one account per environment tier limits the blast radius of a rotation.

**CyberArk and External Secrets Operator**

1. Onboard the Wiz service account as a CyberArk account. The Client ID goes in the username field and the Client Secret in the password field, or use two separate objects.
2. Disable automatic password change by the CPM for this account unless a Wiz-aware rotation process drives it. CyberArk cannot change the secret on the Wiz side by itself, so an unmanaged change would break every Sensor.
3. Grant the identity that the External Secrets Operator uses read access to that object only.
4. Confirm the operator is installed on each cluster and note the name of the CyberArk store (`oc get clustersecretstore`). The operator reaches CyberArk through its Conjur provider. If the clusters have no store yet, `manifests/external-secrets/examples/secretstore-conjur.example.yaml` is a starting point for the platform team.
5. Put the store name and the two CyberArk paths into `manifests/external-secrets/wiz-api-token.yaml`.

**Each OpenShift cluster (platform team)**

1. Create a deployer ServiceAccount for GitLab and store its token as `OPENSHIFT_TOKEN` scoped to the environment `openshift/<cluster>`. The chart creates cluster-scoped objects (SecurityContextConstraints, ClusterRole, ClusterRoleBinding), so the deployer needs cluster-admin or an equivalent custom role. It also needs to create `ExternalSecret` objects in the `wiz` namespace.
2. Confirm the node kernel is supported. OpenShift is supported from OCP 4.9.12 with kernel 4.18.0-305.30.1.el8_4 and later.
3. Open the egress in `NETWORK-EGRESS.md`.

**Images**

The Sensor image is already mirrored internally and this repo does not pull it from Wiz. Get three facts from the team that owns that mirror and put them in `helm/values/base.yaml`:

- the registry host and path prefix (`<SENSOR_IMAGE_REGISTRY>`)
- the repository name (default `sensor`)
- the tag (default `v1`)

Also ask how often that mirror is refreshed. The Sensor only gets new versions when the mirrored copy moves.

## 2. Add a cluster

1. Copy `helm/values/clusters/_template.yaml` to `<cluster>.yaml` and replace the placeholders.
2. Add `<cluster>` to the `CLUSTER` matrix in `.gitlab-ci.yml`.
3. Create the environment-scoped variables for `openshift/<cluster>`.
4. Set `EXTRA_VALUES` for that environment if the cluster needs an overlay.
5. Open a merge request and review the `render` artifact for that cluster.

## 3. Deploy

1. Merge to the default branch.
2. Run the manual `deploy` job for the cluster. Start with one non-production cluster.
3. The job stops if a placeholder remains. It then applies the namespace, applies the `ExternalSecret`, waits until the operator reports it Ready and both keys exist in `wiz-api-token`, runs `helm upgrade --install --wait` and finishes with the validation script.

## 4. Validate

The `deploy` and `verify` jobs check the following.

- `ExternalSecret` `wiz-api-token` is Ready.
- Sensor DaemonSet rolled out on every eligible node.
- Sensor pod admitted under the chart SCC `wiz-sensor-scc`.
- Sensor log contains `ending content update`, which proves authentication and content download.

Then confirm in the Wiz portal.

- Settings > Deployments > Sensors shows the Sensors as Active within about 10 minutes.

Optional end-to-end test: run the Wiz Runtime Sensor Validator from a throwaway pod and look for a Malware Execution event under Explorer > Cloud Events with Origin set to Wiz Sensor. The validator is a benign test file. Use an internally mirrored base image for the test pod.

## 5. Upgrade

1. Change `WIZ_CHART_VERSION` in `.gitlab-ci.yml` through a merge request.
2. Compare the image reference in the `render` output with what the existing Sensor mirror holds.
3. Deploy to non-production first, then production.

The Sensor image tag `v1` is a floating tag. The Sensor version on the clusters follows whatever the existing internal mirror holds, so its refresh cadence is the Sensor upgrade cadence. Pin `wiz-sensor.image.sha256` if change control requires an immutable reference.

## 6. Rollback

```
helm -n wiz history wiz-sensor
helm -n wiz rollback wiz-sensor <revision> --wait
```

Or revert the merge request and re-run `deploy`.

## 7. Uninstall

```
helm -n wiz uninstall wiz-sensor
```

Delete the namespace only when decommissioning, because that also removes the secrets.

## 8. Rotate the Wiz service account secret

Wiz invalidates the old secret the moment a new one is issued. Tokens already issued stay valid for up to 24 hours, so running pods keep working for a while and then fail when they next authenticate. Do the steps below in one sitting.

1. Rotate the secret in Wiz.
2. Update the object in CyberArk.
3. Force the sync on each cluster instead of waiting for `refreshInterval`:
   `oc -n wiz annotate externalsecret wiz-api-token force-sync=$(date +%s) --overwrite`
4. Restart the workloads so they read the new value: `oc -n wiz rollout restart ds`.
5. Run the `verify` job.

A zero-downtime rotation needs two service accounts and a switch of the CyberArk object between them. Plan that separately if it is required.

## 9. Troubleshooting

| Symptom | Check |
|---|---|
| `deploy` stops at "ExternalSecret did not become Ready" | The job prints the operator condition. Usual causes are a wrong store name or kind, a wrong CyberArk path, missing read permission for the operator identity, or an operator version that only serves `external-secrets.io/v1beta1` |
| Pods fail to authenticate after a rotation | The cluster still holds the old value. Force the sync and restart the workloads (section 8) |
| `ImagePullBackOff` | Image and tag exist in the mirror with the same path. If the registry needs credentials enable the `pull-secret` overlay. Remember that the Sensor only uses a pull secret when `imagePullSecret.required` is `true` |
| Sensor pod rejected by admission | The SCC was not created or bound. Confirm `wiz-sensor.openshift: true` and that the deployer could create SecurityContextConstraints |
| No `ending content update` in the Sensor log | Egress to `auth.app.wiz.io`, `agent.us44.app.wiz.io` and `prod-us44-sensor.app.wiz.io`. A TLS-inspecting proxy needs the `proxy` overlay with its CA |
| Sensor missing on some nodes | Node taints. The chart already tolerates control-plane, infra and ODF storage nodes. Add other tolerations in the cluster file |
| Findings appear on the Sensor DaemonSet itself | Expected. Wiz applies its Pod Security Standards rules to its own Sensor. Handle through the normal exception process |

Wiz support package:

```
curl https://downloads.wiz.io/customer-files/kubernetes/wiz_k8s_support_package.sh -o wiz_k8s_support_package.sh
chmod +x wiz_k8s_support_package.sh
./wiz_k8s_support_package.sh --values-file helm/values/base.yaml
```
