{{/*
Expand the name of the chart.
*/}}
{{- define "datadog.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "datadog.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "datadog.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "datadog.labels" -}}
helm.sh/chart: {{ include "datadog.chart" . }}
app.kubernetes.io/component: monitor
{{ include "datadog.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{ include "datafold.labels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "datadog.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}-datadog-agent
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "datadog.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "datadog.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
The datadog deployment tag to use
*/}}
{{- define "datadog.deployment.tag" -}}
{{- if .Values.global.datadog.install -}}
{{-   printf "deployment:%s" (include "datafold.deployment.name" .) }}
{{- end -}}
{{- end -}}

{{/*
The datadog global config for a cloud provider
*/}}
{{- define "datadog.global.config" -}}
{{- if .Values.global.cloudProvider -}}
{{-   if (eq .Values.global.cloudProvider "aws") -}}
criSocketPath: /run/dockershim.sock
{{-   end -}}
{{- end -}}
{{- end -}}

{{/*
The datadog features for a cloud provider
*/}}
{{- define "datadog.features" -}}
{{- if .Values.global.cloudProvider -}}
{{-   if (eq .Values.global.cloudProvider "aws") -}}
admissionController:
  enabled: false
externalMetricsServer:
  enabled: false
  useDatadogMetrics: false
{{-   end -}}
{{- end -}}
{{- end -}}


{{/*
The datadog clusteragent overrides
*/}}
{{- define "datadog.clusteragent.overrides" -}}
{{- if .Values.global.cloudProvider -}}
{{-   if (eq .Values.global.cloudProvider "aws") -}}
clusterAgent:
  image:
    name: gcr.io/datadoghq/cluster-agent:latest
{{-   end -}}
{{- end -}}
{{- end -}}

{{/*
Logging service
*/}}
{{- define "datadog.log.service" -}}
{{ include "datadog.fullname" . }}-logging
{{- end }}
