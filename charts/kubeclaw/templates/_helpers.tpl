{{/*
Validate required secrets when features are enabled.
*/}}
{{- define "kubeclaw.validateValues" -}}
{{- if .Values.tailscale.ssh.enabled }}
  {{- if and (not .Values.tailscale.ssh.authKey) (not .Values.tailscale.ssh.authKeySecretName) }}
    {{- fail "tailscale.ssh.enabled is true but neither tailscale.ssh.authKey nor tailscale.ssh.authKeySecretName is set" }}
  {{- end }}
{{- end }}
{{- if .Values.litellm.enabled }}
  {{- if not .Values.litellm.masterkey }}
    {{- fail "litellm.enabled is true but litellm.masterkey is not set" }}
  {{- end }}
{{- end }}
{{- if .Values.backup.enabled }}
  {{- if not (index .Values.secret.data "S3_BUCKET") }}
    {{- fail "backup.enabled is true but secret.data.S3_BUCKET is not set" }}
  {{- end }}
  {{- if not (index .Values.secret.data "S3_ACCESS_KEY_ID") }}
    {{- fail "backup.enabled is true but secret.data.S3_ACCESS_KEY_ID is not set" }}
  {{- end }}
  {{- if not (index .Values.secret.data "S3_SECRET_ACCESS_KEY") }}
    {{- fail "backup.enabled is true but secret.data.S3_SECRET_ACCESS_KEY is not set" }}
  {{- end }}
{{- end }}
{{- if .Values.gatewayAPI.enabled }}
  {{- if and (not .Values.gatewayAPI.gatewayClassName) (not .Values.gatewayAPI.controller.enabled) }}
    {{- fail "gatewayAPI.enabled is true but neither gatewayAPI.gatewayClassName nor gatewayAPI.controller.enabled is set" }}
  {{- end }}
  {{- if and .Values.gatewayAPI.crds.install .Values.gatewayAPI.controller.enabled }}
    {{- fail "gatewayAPI.crds.install and gatewayAPI.controller.enabled are mutually exclusive — the Envoy Gateway subchart bundles its own CRDs" }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Resolve the effective gatewayClassName.
When gatewayClassName is empty and controller.enabled is true, default to controller.gatewayClassName.
*/}}
{{- define "kubeclaw.gatewayClassName" -}}
{{- if .Values.gatewayAPI.gatewayClassName }}
{{- .Values.gatewayAPI.gatewayClassName }}
{{- else if .Values.gatewayAPI.controller.enabled }}
{{- .Values.gatewayAPI.controller.gatewayClassName }}
{{- end }}
{{- end }}

{{/*
Expand the name of the chart.
*/}}
{{- define "kubeclaw.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncated at 63 chars because some Kubernetes name fields are limited to this.
*/}}
{{- define "kubeclaw.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Name of the Gateway StatefulSet and its headless Service.
*/}}
{{- define "kubeclaw.gatewayName" -}}
{{- printf "%s-gateway" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Create chart label value: "<chart-name>-<chart-version>".
*/}}
{{- define "kubeclaw.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "kubeclaw.labels" -}}
helm.sh/chart: {{ include "kubeclaw.chart" . }}
{{ include "kubeclaw.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels used by the StatefulSet and Service.
*/}}
{{- define "kubeclaw.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kubeclaw.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the Secret that holds gateway credentials.
Returns the existing secret name when set, otherwise the generated name.
*/}}
{{- define "kubeclaw.secretName" -}}
{{- if .Values.secret.existingSecretName }}
{{- .Values.secret.existingSecretName }}
{{- else }}
{{- include "kubeclaw.fullname" . }}
{{- end }}
{{- end }}

{{/*
Name of the desired-config ConfigMap.
*/}}
{{- define "kubeclaw.configmapName" -}}
{{- printf "%s-config" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Name of the init-script ConfigMap.
*/}}
{{- define "kubeclaw.initScriptConfigmapName" -}}
{{- printf "%s-init-script" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Name of the main state PVC (used in volumeClaimTemplates metadata).
*/}}
{{- define "kubeclaw.statePvcName" -}}
{{- printf "%s-state" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Name of the workspace PVC (used in volumeClaimTemplates metadata when splitVolumes=true).
*/}}
{{- define "kubeclaw.workspacePvcName" -}}
{{- printf "%s-workspace" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "kubeclaw.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "kubeclaw.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Checksum annotation for the desired-config ConfigMap.
Including this in the StatefulSet pod template triggers a rollout when config changes.
Usage: {{ include "kubeclaw.configChecksum" . }}
*/}}
{{- define "kubeclaw.configChecksum" -}}
{{- if .Values.config.desired }}
checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
{{- end }}
{{- end }}

{{/*
Checksum annotation for the env ConfigMap.
Triggers rollout when computed env vars change.
Usage: {{ include "kubeclaw.envConfigChecksum" . }}
*/}}
{{- define "kubeclaw.envConfigChecksum" -}}
checksum/env-config: {{ include (print $.Template.BasePath "/env-configmap.yaml") . | sha256sum }}
{{- end }}

{{/*
Image string helper.
*/}}
{{- define "kubeclaw.image" -}}
{{- printf "%s:%s@%s" .Values.image.repository .Values.image.tag .Values.image.digest }}
{{- end }}

{{/*
Name of the Secret holding the Tailscale auth key.
Returns authKeySecretName if set, otherwise "<fullname>-tailscale-authkey".
*/}}
{{- define "kubeclaw.tailscaleAuthKeySecretName" -}}
{{- if .Values.tailscale.ssh.authKeySecretName }}
{{- .Values.tailscale.ssh.authKeySecretName }}
{{- else }}
{{- printf "%s-tailscale-authkey" (include "kubeclaw.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Key within the Tailscale auth key Secret.
*/}}
{{- define "kubeclaw.tailscaleAuthKeySecretKey" -}}
{{- default "TS_AUTHKEY" .Values.tailscale.ssh.authKeySecretKey }}
{{- end }}

{{/*
Tailscale sidecar hostname. Falls back to kubeclaw.fullname.
*/}}
{{- define "kubeclaw.tailscaleHostname" -}}
{{- default (include "kubeclaw.fullname" .) .Values.tailscale.ssh.hostname }}
{{- end }}

{{/*
LiteLLM proxy base URL.
Returns the in-cluster URL of the LiteLLM proxy service on port 4000.
The alias "litellm" in Chart.yaml causes the subchart Service to be named
"<release>-litellm", matching the standard Helm subchart naming convention.
*/}}
{{- define "kubeclaw.litellmBaseUrl" -}}
{{- printf "http://%s-litellm:4000/v1" .Release.Name }}
{{- end }}

{{/*
Name of the egress-filter Deployment and Service.
*/}}
{{- define "kubeclaw.egressFilterName" -}}
{{- printf "%s-egress-filter" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Selector labels for the egress-filter Deployment.
*/}}
{{- define "kubeclaw.egressFilterSelectorLabels" -}}
app.kubernetes.io/name: {{ include "kubeclaw.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: egress-filter
{{- end }}

{{/*
Name of the Chromium Deployment and Service.
*/}}
{{- define "kubeclaw.chromiumName" -}}
{{- printf "%s-chromium" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Selector labels for the Chromium Deployment.
*/}}
{{- define "kubeclaw.chromiumSelectorLabels" -}}
app.kubernetes.io/name: {{ include "kubeclaw.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: chromium
{{- end }}

{{/*
Checksum annotation for the Blocky ConfigMap.
Triggers rollout of the egress-filter Deployment when config changes.
*/}}
{{- define "kubeclaw.blockyConfigChecksum" -}}
{{- if .Values.egressFilter.enabled }}
checksum/blocky-config: {{ include (print $.Template.BasePath "/egress-filter-configmap.yaml") . | sha256sum }}
{{- end }}
{{- end }}

{{/*
Name of the OTel Node Collector DaemonSet.
*/}}
{{- define "kubeclaw.nodeCollectorName" -}}
{{- printf "%s-otel-node" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Selector labels for the OTel Node Collector DaemonSet.
*/}}
{{- define "kubeclaw.nodeCollectorSelectorLabels" -}}
app.kubernetes.io/component: otel-node-collector
{{- end }}

{{/*
Name of the OTel Cluster Collector Deployment.
*/}}
{{- define "kubeclaw.clusterCollectorName" -}}
{{- printf "%s-otel-cluster" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Selector labels for the OTel Cluster Collector Deployment.
*/}}
{{- define "kubeclaw.clusterCollectorSelectorLabels" -}}
app.kubernetes.io/component: otel-cluster-collector
{{- end }}

{{/*
OTel Collector gateway endpoint (ClickStack subchart).
The ClickStack subchart deploys an OTel Collector with a Service named
"<release>-clickstack-otel-collector". OTLP HTTP is on port 4318.
*/}}
{{- define "kubeclaw.otelGatewayEndpoint" -}}
{{- printf "http://%s-clickstack-otel-collector:4318" .Release.Name }}
{{- end }}

{{/*
OTel Collector gateway gRPC endpoint (ClickStack subchart).
OTLP gRPC is on port 4317.
*/}}
{{- define "kubeclaw.otelGatewayGrpcEndpoint" -}}
{{- printf "%s-clickstack-otel-collector:4317" .Release.Name }}
{{- end }}

{{/*
Checksum annotation for the OTel Node Collector ConfigMap.
*/}}
{{- define "kubeclaw.nodeCollectorConfigChecksum" -}}
checksum/otel-node-config: {{ include (print $.Template.BasePath "/otel-node-configmap.yaml") . | sha256sum }}
{{- end }}

{{/*
Checksum annotation for the OTel Cluster Collector ConfigMap.
*/}}
{{- define "kubeclaw.clusterCollectorConfigChecksum" -}}
checksum/otel-cluster-config: {{ include (print $.Template.BasePath "/otel-cluster-configmap.yaml") . | sha256sum }}
{{- end }}

{{/*
Name of the skills-init ConfigMap.
*/}}
{{- define "kubeclaw.skillsConfigmapName" -}}
{{- printf "%s-skills-config" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Name of the Obsidian vault PVC (used in volumeClaimTemplates metadata).
*/}}
{{- define "kubeclaw.obsidianPvcName" -}}
{{- printf "%s-obsidian" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Checksum annotation for the skills ConfigMap.
Triggers rollout when skills config changes.
*/}}
{{- define "kubeclaw.skillsConfigChecksum" -}}
{{- if .Values.skills.enabled }}
checksum/skills-config: {{ include (print $.Template.BasePath "/skills-configmap.yaml") . | sha256sum }}
{{- end }}
{{- end }}

{{/*
Name of the tools-init ConfigMap.
*/}}
{{- define "kubeclaw.toolsConfigmapName" -}}
{{- printf "%s-tools-config" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Checksum annotation for the tools ConfigMap.
Triggers rollout when tools installer config changes.
*/}}
{{- define "kubeclaw.toolsConfigChecksum" -}}
{{- if and .Values.tools.enabled .Values.tools.init.enabled }}
checksum/tools-config: {{ include (print $.Template.BasePath "/tools-configmap.yaml") . | sha256sum }}
{{- end }}
{{- end }}

{{/*
Name of the Gateway API Gateway resource.
*/}}
{{- define "kubeclaw.gatewayAPIName" -}}
{{- printf "%s-gateway-api" (include "kubeclaw.fullname" .) }}
{{- end }}
