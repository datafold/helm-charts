{{/*
    Return the clickhouse host
*/}}
{{- define "datafold.clickhouse.server" -}}
{{- if not .Values.global.clickhouse.server -}}
{{ printf "%s-%s" .Release.Name "clickhouse" }}
{{- else -}}
{{ .Values.global.clickhouse.server }}
{{- end -}}
{{- end -}}

{{/*
    Return the clickhouse port
*/}}
{{- define "datafold.clickhouse.port" -}}
{{- print $.Values.global.clickhouse.port -}}
{{- end -}}
