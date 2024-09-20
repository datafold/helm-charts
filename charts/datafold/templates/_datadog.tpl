{{/*
    Return the datadog host for apm
*/}}
{{- define "datafold.datadog.apm.host" -}}
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

{{/*
    Return the datadog apm port
*/}}
{{- define "datafold.datadog.apm.port" -}}
{{- print $.Values.global.datadog.apm.port -}}
{{- end -}}

