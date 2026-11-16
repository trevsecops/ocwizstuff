# Network egress for the Wiz Runtime Sensor on OpenShift (data center us44)

All traffic is outbound TCP 443 from the cluster nodes. Nothing inbound from Wiz is required.

## From the OpenShift cluster nodes

| FQDN | Purpose |
|---|---|
| `auth.app.wiz.io` | Sensor authentication to the tenant |
| `agent.us44.app.wiz.io` | Download definitions, send logs, report detections |
| `prod-us44-sensor.app.wiz.io` | Sensor to tenant communication |
| `prod-us44-sensor-pubsub.app.wiz.io` | Real-time communication backend |
| Internal registry | Sensor image pull from the existing internal mirror |

Not needed from the cluster because the image is mirrored: `wizio.azurecr.io`, `*.blob.core.windows.net`.

The us44 FQDNs resolve to dynamic IP addresses. A firewall that cannot filter by FQDN needs the static IP option below.

## From the GitLab runner

| Destination | Job | Purpose |
|---|---|---|
| `charts.wiz.io` and `wiz-sec.github.io` | render, deploy | Helm repository index and chart archive. Not needed if `WIZ_HELM_REPO_URL` points at an internal Helm proxy |
| OpenShift API server of each cluster | deploy, verify | `oc` and `helm` |

The runner needs no access to any Wiz container registry.

## From the External Secrets Operator

The operator on each cluster must reach the CyberArk endpoint configured in its secret store. That path is owned by the platform and CyberArk teams.

## Optional: static IP egress (`static-ip` overlay)

Ask Wiz Support to enable Static IP for the tenant. Then allow the Runtime Sensor Static IPs shown under Tenant Info > Wiz IPs. DNS resolution for these names must still work:

- `agent-si.us44.app.wiz.io`
- `prod-us44-sensor-si.app.wiz.io`
- `prod-us44-sensor-pubsub-si.app.wiz.io`

## Optional: Sensor-based Workload Scanner (`workload-scanner` overlay)

| FQDN | Purpose |
|---|---|
| `diskanalyzer-results-source.us-west-2.app.wiz.io` | Upload of scan results |
| `outpost-storage.us44.app.wiz.io` | Tenant settings and Host Configuration Rules |
| `sensor-analysis.us44.app.wiz.io` | SBOM download for vulnerability assessment |
| `logs-ingestion.wiz.io` | Internal logs and metrics |

The Workload Scanner does not support static IP mode.

## Proxies

A TLS-inspecting proxy needs the `proxy` overlay with the proxy CA certificate, otherwise the Sensor rejects the connection.

Wiz publishes a network troubleshooting tool that runs test pods in the cluster against these endpoints. Run it before the first deploy on any cluster behind a strict firewall: https://docs.wiz.io/docs/wiz-deployment-network-troubleshooting-tool
