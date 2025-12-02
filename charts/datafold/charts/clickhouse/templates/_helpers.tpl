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
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else }}
{{- include "clickhouse.name" . }}
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
- name: config
  mountPath: /etc/clickhouse-server/config.d/overrides.xml
  subPath: overrides.xml
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
- name: config
  configMap:
    name: {{ include "clickhouse.xmlconfig" . }}
{{- end }}
{{- end -}}

{{/*
Datadog annotations
*/}}
{{- define "clickhouse.datadog.annotations" -}}
{{- if (eq .Values.global.datadog.install true) }}
ad.datadoghq.com/{{ .Chart.Name }}.logs: >-
  [{
    "source": "clickhouse",
    "service": "clickhouse"
  }]
ad.datadoghq.com/{{ .Chart.Name }}.checks: |
  {
    "clickhouse": {
      "init_config": {},
      "instances": [
      {
        "server": "%%host%%",
        "port":"9000",
        "db":"%%env_CLICKHOUSE_DB%%",
        "username":"%%env_CLICKHOUSE_USER%%",
        "password":"%%env_CLICKHOUSE_PASSWORD%%",
        "service":"clickhouse",
        "metric_patterns": {
          "include": [
            "clickhouse.backup.time",
            "clickhouse.cache.mark.entry.found.total",
            "clickhouse.cache.mark.entry.missed.total",
            "clickhouse.connection.http",
            "clickhouse.connection.tcp",
            "clickhouse.connections.outstanding.total",
            "clickhouse.file.open.*",
            "clickhouse.file.read.*",
            "clickhouse.file.read.fail.count",
            "clickhouse.file.read.slow.count",
            "clickhouse.file.write.*",
            "clickhouse.fs.*",
            "clickhouse.insert.query.time",
            "clickhouse.interface.native.received.bytes.count",
            "clickhouse.interface.native.sent.bytes.count",
            "clickhouse.lock.*",
            "clickhouse.MarkCacheFiles",
            "clickhouse.marks.load.time",
            "clickhouse.merge.active",
            "clickhouse.merge.memory",
            "clickhouse.merge.row.read.count",
            "clickhouse.merge.time",
            "clickhouse.query.*",
            "clickhouse.table.insert.row.count",
            "clickhouse.table.insert.size.count",
            "clickhouse.table.mergetree.insert.delayed.*",
            "clickhouse.table.mergetree.merging.projection.time",
            "clickhouse.table.mergetree.mutation.delayed.*",
            "clickhouse.thread.cpu.wait",
            "clickhouse.thread.io.wait",
            "clickhouse.thread.lock.rw.*",
            "clickhouse.thread.query",
            "clickhouse.UncompressedCacheBytes"
          ],
          "exclude": [
            "clickhouse.*.total"
          ]
        }
      }
      ]
    }
  }
{{- end }}
{{- with .Values.podAnnotations }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}

{{/*
Defines remote storage system to use
*/}}
{{- define "clickhouse.remote_storage" -}}
{{- if .Values.config.remote_storage -}}
{{ .Values.config.remote_storage }}
{{- else if .Values.global.cloudProvider -}}
{{-   if (eq .Values.global.cloudProvider "aws") -}}
"s3"
{{-   else if (eq .Values.global.cloudProvider "gcp") -}}
"gcs"
{{-   else if (eq .Values.global.cloudProvider "azure") -}}
"azblob"
{{-   else -}}
{{      fail .Values.global.cloudProvider " is not a supported cloud provider" }}
{{-   end -}}
{{- else -}}
""
{{- end -}}
{{- end -}}

{{/*
Name of the clickhouse configmap for env location
*/}}
{{- define "clickhouse.configmap" -}}
{{- printf "%s-clickhouse-config" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{/*
Name of the clickhouse config override location
*/}}
{{- define "clickhouse.xmlconfig" -}}
{{- printf "%s-clickhouse-xml-config" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{/*
Name of the clickhouse secrets location
*/}}
{{- define "clickhouse.secrets" -}}
{{- printf "%s-clickhouse-secrets" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end -}}
