{{/*
Expand the name of the chart.
*/}}
{{- define "worker-repo-mirror.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name. Mirrors worker-temporal's pattern for consistency
with `datafold-worker-*` naming in the cluster.
*/}}
{{- define "worker-repo-mirror.fullname" -}}
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
Chart label.
*/}}
{{- define "worker-repo-mirror.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Service Account name.
*/}}
{{- define "worker-repo-mirror.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else }}
{{- include "worker-repo-mirror.name" . }}
{{- end }}
{{- end }}

{{/*
Service name. The parent chart can reach the service at
`<svc-name>.<release-namespace>.svc`.
*/}}
{{- define "worker-repo-mirror.serviceName" -}}
{{- default "repo-mirror" .Values.service.name }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "worker-repo-mirror.labels" -}}
helm.sh/chart: {{ include "worker-repo-mirror.chart" . }}
app.kubernetes.io/component: {{ include "worker-repo-mirror.name" . }}
{{ include "worker-repo-mirror.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{ include "datafold.labels" . }}
{{- end }}

{{/*
Selector labels. `part-of: datafold` matches the convention used by every
other Datafold workload — gives all workers a single selector for
namespace-wide policies.
*/}}
{{- define "worker-repo-mirror.selectorLabels" -}}
app.kubernetes.io/name: {{ include "worker-repo-mirror.name" . }}
app.kubernetes.io/part-of: datafold
{{- end }}

{{/*
Datadog log autodiscovery annotation. Same shape as worker-temporal so
log routing is uniform.
*/}}
{{- define "worker-repo-mirror.datadog.annotations" -}}
{{- if (eq .Values.global.datadog.install true) }}
ad.datadoghq.com/{{ .Chart.Name }}.logs: >-
  [{
    "source": "datafold-{{ .Chart.Name }}",
    "service": "datafold-{{ .Chart.Name }}",
    "log_processing_rules": [{
      "type": "multi_line",
      "name": "log_start_with_date",
      "pattern" : "\\[\\d{4}-\\d{2}-\\d{2}\\s\\d{2}:\\d{2}:\\d{2}\\,\\d{3}\\]"
    }]
  }]
{{- end }}
{{- end }}

{{/*
Datafold annotations. Keeps replica-count visible in `kubectl describe pod`,
matching the worker-temporal convention.
*/}}
{{- define "worker-repo-mirror.datafold.annotations" -}}
replica-count: "{{ .Values.replicaCount }}"
{{- with .Values.podAnnotations }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}

{{/*
PVC storageClassName resolution. Precedence:
  1. .Values.storage.storageClass (per-env override)
  2. global.temporal.storageClassName (cluster-wide default for temporal workers)
  3. literal "sc-datafold-temporal" (cluster default name)
Mirrors worker-temporal's helper of the same shape.
*/}}
{{- define "worker-repo-mirror.effectiveStorageClassName" -}}
{{- if .Values.storage.storageClass -}}
{{- .Values.storage.storageClass | toString | trim -}}
{{- else if and .Values.global.temporal .Values.global.temporal.storageClassName -}}
{{- .Values.global.temporal.storageClassName | toString | trim -}}
{{- else -}}
sc-datafold-temporal
{{- end -}}
{{- end }}
