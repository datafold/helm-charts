{{/*
    Return the server port
*/}}
{{- define "datafold.server.port" -}}
{{- print $.Values.global.server.port -}}
{{- end -}}

{{/*
    Return the server host name
*/}}
{{- define "datafold.server.hostname" -}}
{{- print $.Values.global.server.hostName -}}
{{- end -}}
