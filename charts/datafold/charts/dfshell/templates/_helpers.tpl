{{/*
Expand the name of the chart.
*/}}
{{- define "dfshell.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "dfshell.fullname" -}}
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
{{- define "dfshell.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "dfshell.labels" -}}
helm.sh/chart: {{ include "dfshell.chart" . }}
app.kubernetes.io/component: command-line
{{ include "dfshell.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{ include "datafold.labels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "dfshell.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dfshell.name" . }}
app.kubernetes.io/part-of: datafold
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "dfshell.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "dfshell.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Datadog annotations
*/}}
{{- define "dfshell.datadog.annotations" -}}
{{- if (eq .Values.global.datadog.install true) }}
ad.datadoghq.com/{{ .Chart.Name }}.logs: >-
  [{
    "source": "datafold-server-onprem",
    "service": "datafold-server-onprem",
    "log_processing_rules": [{
      "type": "multi_line",
      "name": "log_start_with_date",
      "pattern" : "\\d{4}-(0?[1-9]|1[012])-(0?[1-9]|[12][0-9]|3[01])"
    }]
  }]
{{- end }}
{{- with .Values.podAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end }}

