{{/*
    Return the datadog host for logs
*/}}
{{- define "datafold.datadog.logs.host" -}}
{{- if not .Values.global.datadog.host -}}
{{ printf "%s-%s" .Release.Name "datadog" }}
{{- else -}}
{{ .Values.global.datadog.host }}
{{- end -}}
{{- end -}}

{{/*
    Return the datadog host for metrics
*/}}
{{- define "datafold.datadog.metrics.host" -}}
{{- printf "%s-%s" .Release.Name "datadog-agent" | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{/*
    Return the datadog log port
*/}}
{{- define "datafold.datadog.logs.port" -}}
{{- print $.Values.global.datadog.logs.port -}}
{{- end -}}

{{/*
    Return the datadog metrics port
*/}}
{{- define "datafold.datadog.metrics.port" -}}
{{- print $.Values.global.datadog.metrics.port -}}
{{- end -}}
