{{/*
Expand the name of the chart.
*/}}
{{- define "kept.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "kept.fullname" -}}
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
{{- define "kept.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kept.labels" -}}
helm.sh/chart: {{ include "kept.chart" . }}
app.kubernetes.io/component: database
{{ include "kept.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{ include "datafold.labels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kept.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kept.name" . }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "kept.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "kept.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the kept data volume
*/}}
{{- define "kept.data.pv.name" -}}
{{- include "kept.name" . }}-data-volume
{{- end -}}

{{/*
Name of the kept data volume claim
*/}}
{{- define "kept.data.pvc.name" -}}
{{- include "kept.name" . }}-data-claim
{{- end -}}

{{/*
Volume mounts when PV is used
*/}}
{{- define "kept.volume.mounts" -}}
{{- if (ne .Values.global.kept.storageOnPV "false") }}
- name: data
  mountPath: /data
{{- end -}}
{{- end -}}

{{/*
Volumes when PV is used
*/}}
{{- define "kept.volumes" -}}
{{- if (ne .Values.global.kept.storageOnPV "false") }}
- name: data
  persistentVolumeClaim:
    claimName: {{ include "kept.data.pvc.name" . }}
{{- end }}
{{- end -}}

{{/*
Datadog annotations
*/}}
{{- define "kept.datadog.annotations" -}}
{{- if (eq .Values.global.datadog.install true) }}
ad.datadoghq.com/{{ .Chart.Name }}.logs: >-
  [{
    "source": "kept",
    "service": "kept"
  }]
{{- end }}
{{- with .Values.podAnnotations }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}
