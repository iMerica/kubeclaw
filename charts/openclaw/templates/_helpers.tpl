{{/*
Expand the name of the chart.
*/}}
{{- define "openclaw.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncated at 63 chars because some Kubernetes name fields are limited to this.
*/}}
{{- define "openclaw.fullname" -}}
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
{{- define "openclaw.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "openclaw.labels" -}}
helm.sh/chart: {{ include "openclaw.chart" . }}
{{ include "openclaw.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels used by the StatefulSet and Service.
*/}}
{{- define "openclaw.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openclaw.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the Secret that holds gateway credentials.
Returns the existing secret name when set, otherwise the generated name.
*/}}
{{- define "openclaw.secretName" -}}
{{- if .Values.secret.existingSecretName }}
{{- .Values.secret.existingSecretName }}
{{- else }}
{{- include "openclaw.fullname" . }}
{{- end }}
{{- end }}

{{/*
Name of the desired-config ConfigMap.
*/}}
{{- define "openclaw.configmapName" -}}
{{- printf "%s-config" (include "openclaw.fullname" .) }}
{{- end }}

{{/*
Name of the init-script ConfigMap.
*/}}
{{- define "openclaw.initScriptConfigmapName" -}}
{{- printf "%s-init-script" (include "openclaw.fullname" .) }}
{{- end }}

{{/*
Name of the main state PVC (used in volumeClaimTemplates metadata).
*/}}
{{- define "openclaw.statePvcName" -}}
{{- printf "%s-state" (include "openclaw.fullname" .) }}
{{- end }}

{{/*
Name of the workspace PVC (used in volumeClaimTemplates metadata when splitVolumes=true).
*/}}
{{- define "openclaw.workspacePvcName" -}}
{{- printf "%s-workspace" (include "openclaw.fullname" .) }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "openclaw.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "openclaw.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Checksum annotation for the desired-config ConfigMap.
Including this in the StatefulSet pod template triggers a rollout when config changes.
Usage: {{ include "openclaw.configChecksum" . }}
*/}}
{{- define "openclaw.configChecksum" -}}
{{- if .Values.config.desired }}
checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
{{- end }}
{{- end }}

{{/*
Image string helper.
*/}}
{{- define "openclaw.image" -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- end }}
