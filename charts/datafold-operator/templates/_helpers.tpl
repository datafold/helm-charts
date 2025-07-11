{{/*
Expand the name of the chart.
*/}}
{{- define "datafold-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "datafold-operator.fullname" -}}
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
{{- define "datafold-operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "datafold-operator.labels" -}}
helm.sh/chart: {{ include "datafold-operator.chart" . }}
meta.helm.sh/release-name: datafold-operator
meta.helm.sh/release-namespace: {{ include "datafold-operator.namespace" . }}
{{ include "datafold-operator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "datafold-operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "datafold-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "datafold-operator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "datafold-operator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the namespace to use
*/}}
{{- define "datafold-operator.namespace" -}}
{{- .Values.namespace.name | default "datafold-system" }}
{{- end }}

{{/*
Generate environment variables for the operator
*/}}
{{- define "datafold-operator.env" -}}
# Required environment variables (always present)
- name: POD_NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
{{- with .Values.env }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }} 