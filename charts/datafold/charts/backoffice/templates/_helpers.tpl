{{/*
Expand the name of the chart.
*/}}
{{- define "backoffice.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "backoffice.fullname" -}}
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
{{- define "backoffice.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "backoffice.labels" -}}
helm.sh/chart: {{ include "backoffice.chart" . }}
app.kubernetes.io/component: command-line
{{ include "backoffice.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{ include "datafold.labels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "backoffice.selectorLabels" -}}
app.kubernetes.io/name: {{ include "backoffice.name" . }}
app.kubernetes.io/part-of: datafold
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "backoffice.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "backoffice.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Datadog annotations
*/}}
{{- define "backoffice.datadog.annotations" -}}
{{- if (eq .Values.global.datadog.install true) }}
ad.datadoghq.com/{{ .Chart.Name }}.logs: >-
  [{
    "source": "datafold-server-onprem",
    "service": "datafold-server-onprem",
    "log_processing_rules": [{
      "type": "multi_line",
      "name": "log_start_with_date",
      "pattern" : "\\[\\d{4}-\\d{2}-\\d{2}\\s\\d{2}:\\d{2}:\\d{2}\\,\\d{3}\\]"
    }]
  }]
{{- end }}
{{- end }}

{{/*
Datafold annotations
*/}}
{{- define "backoffice.datafold.annotations" -}}
replica-count: "{{ .Values.replicaCount }}"
{{- with .Values.podAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end }}

