{{/*
    Return the kept host
*/}}
{{- define "datafold.kept.server" -}}
{{- if not .Values.global.kept.server -}}
{{ printf "%s-%s" .Release.Name "kept" }}
{{- else -}}
{{ .Values.global.kept.server }}
{{- end -}}
{{- end -}}

{{/*
    Return the kept port
*/}}
{{- define "datafold.kept.port" -}}
{{- print $.Values.global.kept.port -}}
{{- end -}}
