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
Name of the Secret holding the LiteLLM master key.
Returns the user-provided secret name or the auto-generated default.
*/}}
{{- define "kubeclaw.litellmMasterkeySecretName" -}}
{{- if .Values.litellm.masterkeySecretName }}
{{- .Values.litellm.masterkeySecretName }}
{{- else }}
{{- printf "%s-litellm-masterkey" (include "kubeclaw.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Key name within the LiteLLM master key Secret.
*/}}
{{- define "kubeclaw.litellmMasterkeySecretKey" -}}
{{- default "masterkey" .Values.litellm.masterkeySecretKey }}
{{- end }}
