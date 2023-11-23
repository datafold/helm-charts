{{/*
    Return the redis host
*/}}
{{- define "datafold.redis.server" -}}
{{- if not .Values.global.redis.server -}}
{{ printf "%s-%s" .Release.Name "redis" }}
{{- else -}}
{{ .Values.global.redis.server }}
{{- end -}}
{{- end -}}

{{/*
    Return the redis port
*/}}
{{- define "datafold.redis.port" -}}
{{- print $.Values.global.redis.port -}}
{{- end -}}
