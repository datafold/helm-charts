{{/*
    Return the postgres host
*/}}
{{- define "datafold.postgres.server" -}}
{{- if not .Values.global.postgres.server -}}
{{ printf "%s-%s" .Release.Name "postgres" }}
{{- else -}}
{{ .Values.global.postgres.server }}
{{- end -}}
{{- end -}}

{{/*
    Return the postgres port
*/}}
{{- define "datafold.postgres.port" -}}
{{- print $.Values.global.postgres.port -}}
{{- end -}}

{{/*
    Return the postgres password of the datadog user 
*/}}
{{- define "datafold.postgres.datadogpw" -}}
{{- print $.Values.global.postgres.datadogpw -}}
{{- end -}}

