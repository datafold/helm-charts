{{/*
Expand the name of the chart.
*/}}
{{- define "memgraph.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "memgraph.fullname" -}}
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
{{- define "memgraph.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "memgraph.labels" -}}
helm.sh/chart: {{ include "memgraph.chart" . }}
app.kubernetes.io/component: database
{{ include "memgraph.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{ include "datafold.labels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "memgraph.selectorLabels" -}}
app.kubernetes.io/name: {{ include "memgraph.name" . }}
{{- end }}

{{/*
Name of the memgraph data volume claim
*/}}
{{- define "memgraph.pvc.name" -}}
{{- include "memgraph.name" . }}-data-claim
{{- end -}}

{{/*
Name of the memgraph data volume
*/}}
{{- define "memgraph.pv.name" -}}
{{- include "memgraph.name" . }}-data-volume
{{- end -}}

{{/*
Volume mounts when PV is used
*/}}
{{- define "memgraph.volume.mounts" -}}
{{- if (ne .Values.global.memgraph.storageOnPV "false") }}
- name: data
  mountPath: /var/lib/memgraph
{{- end -}}
{{- end -}}

{{/*
Volumes when PV is used
*/}}
{{- define "memgraph.volumes" -}}
{{- if (ne .Values.global.memgraph.storageOnPV "false") }}
- name: data
  persistentVolumeClaim:
    claimName: {{ include "memgraph.pvc.name" . }}
{{- end }}
{{- end -}}

{{/*
Datadog annotations
*/}}
{{- define "memgraph.datadog.annotations" -}}
{{- if (eq .Values.global.datadog.install true) }}
ad.datadoghq.com/{{ .Chart.Name }}.logs: >-
  [{
    "source": "memgraph",
    "service": "memgraph"
  }]
{{- end }}
{{- with .Values.podAnnotations }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}
