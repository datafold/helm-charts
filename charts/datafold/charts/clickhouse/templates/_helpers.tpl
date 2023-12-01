{{/*
Expand the name of the chart.
*/}}
{{- define "clickhouse.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "clickhouse.fullname" -}}
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
{{- define "clickhouse.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "clickhouse.labels" -}}
helm.sh/chart: {{ include "clickhouse.chart" . }}
app.kubernetes.io/component: database
{{ include "clickhouse.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{ include "datafold.labels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "clickhouse.selectorLabels" -}}
app.kubernetes.io/name: {{ include "clickhouse.name" . }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "clickhouse.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "clickhouse.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the clickhouse data volume
*/}}
{{- define "clickhouse.data.pv.name" -}}
{{- include "clickhouse.name" . }}-data-volume
{{- end -}}

{{/*
Name of the clickhouse logs volume
*/}}
{{- define "clickhouse.logs.pv.name" -}}
{{- include "clickhouse.name" . }}-logs-volume
{{- end -}}

{{/*
Name of the clickhouse data volume claim
*/}}
{{- define "clickhouse.data.pvc.name" -}}
{{- include "clickhouse.name" . }}-data-claim
{{- end -}}

{{/*
Name of the clickhouse logs volume claim
*/}}
{{- define "clickhouse.logs.pvc.name" -}}
{{- include "clickhouse.name" . }}-logs-claim
{{- end -}}

{{/*
Volume mounts when PV is used
*/}}
{{- define "clickhouse.volume.mounts" -}}
{{- if (ne .Values.global.clickhouse.storageOnPV "false") }}
- name: data
  mountPath: /var/lib/clickhouse
- name: logs
  mountPath: /var/log/clickhouse-server
{{- end -}}
{{- end -}}

{{/*
Volumes when PV is used
*/}}
{{- define "clickhouse.volumes" -}}
{{- if (ne .Values.global.clickhouse.storageOnPV "false") }}
- name: data
  persistentVolumeClaim:
    claimName: {{ include "clickhouse.data.pvc.name" . }}
- name: logs
  persistentVolumeClaim:
    claimName: {{ include "clickhouse.logs.pvc.name" . }}
{{- end }}
{{- end -}}
