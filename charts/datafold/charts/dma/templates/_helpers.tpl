{{/*
Expand the name of the chart.
*/}}
{{- define "dma.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "dma.fullname" -}}
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
{{- define "dma.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "dma.labels" -}}
helm.sh/chart: {{ include "dma.chart" . }}
app.kubernetes.io/component: {{ include "dma.name" . }}
{{ include "dma.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{ include "datafold.labels" . }}
{{- end }}

{{- define "dma.templatelabels" -}}
{{- if .Values.isTemplate }}
datafold.com/dma-type: template
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "dma.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dma.name" . }}
{{- end }}

{{/*
Datadog annotations
*/}}
{{- define "dma.datadog.annotations" -}}
{{- if (eq .Values.global.datadog.install true) }}
ad.datadoghq.com/{{ .Chart.Name }}.logs: >-
  [{
    "source": "datafold-dma-onprem",
    "service": "datafold-dma-onprem",
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
{{- define "dma.datafold.annotations" -}}
replica-count: "{{ .Values.replicaCount }}"
{{- with .Values.podAnnotations }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}

{{/*
DMA resource names with consistent prefixing
*/}}
{{- define "dma.names.statefulset" -}}
{{- if .Values.prefix }}
{{- printf "%s-%s-dma-statefulset" .Release.Name .Values.prefix }}
{{- else }}
{{- printf "%s-dma-statefulset" .Release.Name }}
{{- end }}
{{- end }}

{{- define "dma.names.service" -}}
{{- if .Values.prefix }}
{{- printf "%s-%s-dma-headless" .Release.Name .Values.prefix }}
{{- else }}
{{- printf "%s-dma-headless" .Release.Name }}
{{- end }}
{{- end }}

{{- define "dma.names.serviceaccount" -}}
dma
{{- end }}

{{- define "dma.names.volumeClaimTemplate" -}}
dma-data
{{- end }}

{{- define "dma.names.pvc" -}}
{{- if .Values.prefix }}
{{- printf "%s-%s-dma-data" .Release.Name .Values.prefix }}
{{- else }}
{{- printf "%s-dma-data" .Release.Name }}
{{- end }}
{{- end }}

{{/*
Shared SSH resource names (not prefixed - shared across all DMA instances)
*/}}
{{- define "dma.names.shared-configmap" -}}
{{- printf "%s-dma-sshd-config" .Release.Name }}
{{- end }}

{{- define "dma.names.shared-ssh-host-keys" -}}
{{- printf "%s-dma-ssh-host-keys" .Release.Name }}
{{- end }}

{{- define "dma.names.shared-ssh-keygen-job" -}}
{{- printf "%s-dma-ssh-keygen" .Release.Name }}
{{- end }}
