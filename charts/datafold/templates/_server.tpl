{{/*
    Return the server host
*/}}
{{- define "datafold.server.server" -}}
{{- if not .Values.global.server.server -}}
{{ printf "%s-%s" .Release.Name "redis" }}
{{- else -}}
{{ .Values.global.server.server }}
{{- end -}}
{{- end -}}

{{/*
    Return the server port
*/}}
{{- define "datafold.server.port" -}}
{{- print $.Values.global.server.port -}}
{{- end -}}
