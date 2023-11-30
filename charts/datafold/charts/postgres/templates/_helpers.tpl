{{/*
Expand the name of the chart.
*/}}
{{- define "postgres.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "postgres.fullname" -}}
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
{{- define "postgres.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "postgres.labels" -}}
helm.sh/chart: {{ include "postgres.chart" . }}
app.kubernetes.io/component: database
{{ include "postgres.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{ include "datafold.labels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "postgres.selectorLabels" -}}
app.kubernetes.io/name: {{ include "postgres.name" . }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "postgres.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "postgres.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the postgres data volume
*/}}
{{- define "postgres.data.pv.name" -}}
{{- include "postgres.name" . }}-data-volume
{{- end -}}

{{/*
Name of the postgres data volume claim
*/}}
{{- define "postgres.data.pvc.name" -}}
{{- include "postgres.name" . }}-data-claim
{{- end -}}

{{/*
Volume mounts when PV is used
*/}}
{{- define "postgres.volume.mounts" -}}
{{- if (ne .Values.global.postgres.storageOnPV "false") }}
- name: data
  mountPath: /var/lib/postgresql/data
{{- end -}}
{{- end -}}

{{/*
Volumes when PV is used
*/}}
{{- define "postgres.volumes" -}}
{{- if (ne .Values.global.postgres.storageOnPV "false") }}
- name: data
  persistentVolumeClaim:
    claimName: {{ include "postgres.data.pvc.name" . }}
{{- end }}
{{- end -}}

{{/*
Datadog annotations
*/}}
{{- define "postgres.datadog.annotations" -}}
{{- if (eq .Values.global.datadog.install true) }}
ad.datadoghq.com/{{ .Chart.Name }}.logs: >-
  [{
    "source": "postgres",
    "service": "postgres"
  }]
{{- end }}
{{- with .Values.podAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end }}
