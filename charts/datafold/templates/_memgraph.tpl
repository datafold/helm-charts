{{/*
    Return the memgraph host
*/}}
{{- define "datafold.memgraph.server" -}}
{{- if not .Values.global.memgraph.server -}}
{{ printf "%s-%s" .Release.Name "memgraph" }}
{{- else -}}
{{ .Values.global.memgraph.server }}
{{- end -}}
{{- end -}}

{{/*
    Return the memgraph port
*/}}
{{- define "datafold.memgraph.port" -}}
{{- print $.Values.global.memgraph.port -}}
{{- end -}}
