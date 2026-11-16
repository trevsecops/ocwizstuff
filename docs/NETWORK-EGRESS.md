# Network egress for Wiz on OpenShift (data center us44)

All traffic is outbound TCP 443. Nothing inbound from Wiz is required because the Broker opens the tunnel from inside the cluster.

## From the OpenShift cluster nodes and pods

| FQDN | Used by | Purpose |
|---|---|---|
| `auth.app.wiz.io` | Sensor, Connector, Broker | Authentication to the tenant |
| `agent.us44.app.wiz.io` | Sensor, Connector, Broker | Tenant communication. The Broker requires HTTP/2 on this path |
| `prod-us44-sensor.app.wiz.io` | Sensor | Definitions, logs and detections |
| `prod-us44-sensor-pubsub.app.wiz.io` | Sensor | Real-time communication backend |
| `logs-ingestion.wiz.io` | Broker 3.x | Telemetry |
| `tunnel.us44.app.wiz.io` | Broker | Listed in the Connector requirements. The Broker page marks it as needed only before Broker 3.0.0. Request it to be safe |
| Internal registry | Nodes | Image pulls for the Sensor and Broker from the internal mirror |

Not needed from the cluster when images are mirrored: `wizio.azurecr.io`, `wiziopublic.azurecr.io`, `*.blob.core.windows.net`.

The us44 FQDNs resolve to dynamic IP addresses. A firewall that cannot filter by FQDN needs the static IP option below.

## From the GitLab runner

| FQDN | Job | Purpose |
|---|---|---|
| `charts.wiz.io` and `wiz-sec.github.io` | render, deploy | Helm repository index and chart archives. Not needed if `WIZ_HELM_REPO_URL` points at an internal Helm proxy |
| `wiziopublic.azurecr.io` | mirror-images | Broker image source. Only if this repo mirrors the Broker |
| `*.blob.core.windows.net` | mirror-images | Azure Container Registry data endpoints |
| OpenShift API server of each cluster | deploy, verify | `oc` and `helm` |
| Internal registry | mirror-images | Push target for the Broker image |

The runner needs no access to `wizio.azurecr.io`. The Sensor image is supplied by the existing internal mirror.

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

A TLS-inspecting proxy needs the `proxy` overlay with the proxy CA certificate, otherwise the Sensor rejects the connection. Zscaler disables HTTP/2 by default and the Broker needs it.

Wiz publishes a network troubleshooting tool that runs test pods in the cluster against these endpoints. Run it before the first deploy on any cluster behind a strict firewall: https://docs.wiz.io/docs/wiz-deployment-network-troubleshooting-tool
