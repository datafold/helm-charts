{{/*
    Return the datadog host for logs
*/}}
{{- define "datafold.datadog.logs.host" -}}
{{- if not .Values.global.datadog.host -}}
{{ printf "%s-%s-logging" .Release.Name "datadog" }}
{{- else -}}
{{ .Values.global.datadog.host }}
{{- end -}}
{{- end -}}

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

{{/*
    Return the datadog postgres password
*/}}
{{- define "datafold.datadog.postgres.pw" -}}
{{- printf "ENC[k8s_secret@%s/%s-secrets/DATAFOLD_DATADOG_PW]" $.Values.global.deployment .Release.Name -}}
{{- end -}}
