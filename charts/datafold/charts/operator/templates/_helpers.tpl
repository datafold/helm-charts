{{/*
Expand the name of the chart.
*/}}
{{- define "operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Base fully qualified app name without secondary deployment suffix.
Used as the ClusterRole name (shared across deployments) and as the
foundation for operator.fullname.
*/}}
{{- define "operator.baseName" -}}
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
Create a default fully qualified app name.
For secondary deployments, appends the namespace to avoid cluster-scoped name clashes.
*/}}
{{- define "operator.fullname" -}}
{{- include "operator.baseName" . -}}
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
Name of the ClusterRole to bind to: existingClusterRoleName when set,
otherwise the base name (without namespace suffix) which matches the primary's ClusterRole.
*/}}
{{- define "operator.clusterRoleName" -}}
{{- if .Values.existingClusterRoleName -}}
{{- .Values.existingClusterRoleName -}}
{{- else -}}
{{- include "operator.baseName" . -}}
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
{{ .Values.image.tagOverride | default .Chart.AppVersion }}
{{- end }}
