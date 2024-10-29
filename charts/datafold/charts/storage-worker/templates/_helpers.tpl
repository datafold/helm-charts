{{/*
Expand the name of the chart.
*/}}
{{- define "worker.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "worker.fullname" -}}
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
{{- define "worker.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "worker.labels" -}}
helm.sh/chart: {{ include "worker.chart" . }}
app.kubernetes.io/component: {{ include "worker.name" . }}
{{ include "worker.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{ include "datafold.labels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "worker.selectorLabels" -}}
app.kubernetes.io/name: {{ include "worker.name" . }}
app.kubernetes.io/part-of: datafold
{{- end }}

{{/*
Worker queues
*/}}
{{- define "worker.env" -}}
- name: QUEUES
  value: "{{ .Values.worker.queues }}"
- name: WORKERS_COUNT
  value: "{{ .Values.worker.count }}"
- name: MAX_TASKS_PER_WORKER
  value: "{{ .Values.worker.tasks }}"
- name: MAX_MEMORY_PER_WORKER
  value: "{{ .Values.worker.memory }}"
{{- end -}}

{{/*
Name of the worker data volume claim
*/}}
{{- define "worker.data.pvc.name" -}}
{{- include "worker.name" . }}-scratch-claim
{{- end -}}

{{/*
Volumes
*/}}
{{- define "worker.volumes" -}}
- name: data
  ephemeral:
    volumeClaimTemplate:
      metadata:
        labels:
          {{- include "worker.labels" . | nindent 8 }}
      spec:
        accessModes: [ "ReadWriteOnce" ]
        storageClassName: {{ .Values.storage.storageClass | quote }}
        resources:
          requests:
            storage: {{ .Values.storage.dataSize | quote }}
{{- end -}}

{{/*
Volume mounts for scratch local storage if enabled
*/}}
{{- define "worker.volume.mounts" -}}
- name: data
  mountPath: /data
{{- end -}}

{{/*
Datadog annotations
*/}}
{{- define "worker.datadog.annotations" -}}
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
{{- define "worker.datafold.annotations" -}}
replica-count: "{{ .Values.replicaCount }}"
{{- with .Values.podAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end }}
