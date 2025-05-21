{{/*
Expand the name of the chart.
*/}}
{{- define "datadog.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "datadog.fullname" -}}
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
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "datadog.fullname.agent" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s-agent" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "datadog.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "datadog.labels" -}}
helm.sh/chart: {{ include "datadog.chart" . }}
app.kubernetes.io/component: monitor
{{ include "datadog.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{ include "datafold.labels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "datadog.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}-datadog-agent
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "datadog.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "datadog.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
The datadog global config for a cloud provider
*/}}
{{- define "datadog.global.config" -}}
{{- if .Values.global.cloudProvider -}}
{{-   if (eq .Values.global.cloudProvider "aws") -}}
criSocketPath: /run/dockershim.sock
{{-   end -}}
{{- end -}}
{{- end -}}

{{/*
The datadog features for a cloud provider
*/}}
{{- define "datadog.features" -}}
{{- if .Values.global.cloudProvider -}}
{{-   if (eq .Values.global.cloudProvider "aws") -}}
admissionController:
  enabled: false
externalMetricsServer:
  enabled: false
  useDatadogMetrics: false
{{-   end -}}
{{- end -}}
{{- end -}}

{{/*
The datadog clusteragent overrides
*/}}
{{- define "datadog.clusteragent.overrides" -}}
clusterAgent:
  image:
    name: gcr.io/datadoghq/cluster-agent:latest
{{-     if (eq .Values.configuration.monitorPostgres true) }}
  extraConfd:
    configDataMap:
      postgres.yaml: |-
        cluster_check: true
        init_config:
        instances:
          - dbm: true
            host: {{ include "datafold.postgres.server" . }}
            port: {{ include "datafold.postgres.port" . }}
            username: datadog
            password: {{ include "datafold.datadog.postgres.pw" . }}
            ssl: require
            exclude_hostname: true
            dbname: {{ include "datafold.datadog.postgres.database" . }}
            dbstrict: true
            collect_activity_metrics: true
            query_metrics:
              enabled: false
              collection_interval: 10
            query_samples:
              enabled: false
            query_activity:
              enabled: true
            query_timeout: 5000

{{- end -}}
{{- end -}}

{{/*
Logging service
*/}}
{{- define "datadog.log.service" -}}
{{ include "datadog.fullname" . }}-logging
{{- end }}

{{/*
Cluster checks boolean
*/}}
{{- define "datadog.clusterChecks" -}}
{{- if (eq .Values.configuration.clusterChecks true) -}}
clusterChecks:
  enabled: true
{{- end -}}
{{- end -}}
