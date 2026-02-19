{{/*
Expand the name of the chart.
*/}}
{{- define "operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "operator.fullname" -}}
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
{{- if .Values.global.secondaryDeployment -}}-{{- .Release.Namespace -}}{{- end -}}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "operator.labels" -}}
helm.sh/chart: {{ include "operator.chart" . }}
{{ include "operator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the ClusterRole to bind to: existingClusterRoleName when set (secondary install),
otherwise the role we create (fullname) for the primary install.
*/}}
{{- define "operator.clusterRoleName" -}}
{{- if .Values.existingClusterRoleName -}}
{{- .Values.existingClusterRoleName -}}
{{- else -}}
{{- include "operator.fullname" . -}}
{{- end -}}
{{- end -}}

{{/*
Datadog annotations
*/}}
{{- define "operator.datadog.annotations" -}}
{{- if (eq .Values.global.datadog.install true) }}
ad.datadoghq.com/{{ .Chart.Name }}.logs: >-
  [{
    "source": "datafold-operator",
    "service": "datafold-operator",
    "log_processing_rules": [{
      "type": "multi_line",
      "name": "log_start_with_date",
      "pattern" : "\\[\\d{4}-\\d{2}-\\d{2}\\s\\d{2}:\\d{2}:\\d{2}\\,\\d{3}\\]"
    }]
  }]
{{- end }}
{{- with .Values.podAnnotations }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}

{{/*
Helper to determine version
*/}}
{{- define "operator.version" -}}
{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end }}
