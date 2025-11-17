{{/*
Expand the name of the chart.
*/}}
{{- define "redis.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "redis.fullname" -}}
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
{{- define "redis.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "redis.labels" -}}
helm.sh/chart: {{ include "redis.chart" . }}
app.kubernetes.io/component: database
{{ include "redis.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{ include "datafold.labels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "redis.selectorLabels" -}}
app.kubernetes.io/name: {{ include "redis.name" . }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "redis.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "redis.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the redis data volume
*/}}
{{- define "redis.data.pv.name" -}}
{{- include "redis.name" . }}-data-volume
{{- end -}}

{{/*
Name of the redis data volume claim
*/}}
{{- define "redis.data.pvc.name" -}}
{{- include "redis.name" . }}-data-claim
{{- end -}}

{{/*
Volume mounts when PV is used
*/}}
{{- define "redis.volume.mounts" -}}
{{- if (ne .Values.global.redis.storageOnPV "false") }}
- name: data
  mountPath: /data
{{- end -}}
{{- end -}}

{{/*
Volumes when PV is used
*/}}
{{- define "redis.volumes" -}}
{{- if (ne .Values.global.redis.storageOnPV "false") }}
- name: data
  persistentVolumeClaim:
    claimName: {{ include "redis.data.pvc.name" . }}
{{- end }}
{{- end -}}

{{/*
Datadog annotations
*/}}
{{- define "redis.datadog.annotations" -}}
{{- if (eq .Values.global.datadog.install true) }}
ad.datadoghq.com/{{ .Chart.Name }}.logs: >-
  [{
    "source": "redis",
    "service": "redis"
  }]
ad.datadoghq.com/redis.checks: |
  {
    "redisdb": {
      "init_config": {},
      "instances": [
      {
        "host": "%%host%%",
          "port":"6379",
          "password":"%%env_REDIS_PASSWORD%%"
        }
      ]
    }
  }
{{- end }}
{{- with .Values.podAnnotations }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}
