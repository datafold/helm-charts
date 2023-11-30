{{/*
    Return the server host
*/}}
{{- define "datafold.server.server" -}}
{{- if not .Values.global.server.server -}}
{{ printf "%s-%s" .Release.Name "server" }}
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

{{/*
    Return the server host name
*/}}
{{- define "datafold.server.hostname" -}}
{{- print $.Values.global.serverName -}}
{{- end -}}

{{/*
Expand the name of the chart.
*/}}
{{- define "datafold.server.name" -}}
{{- default "server"  | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "datafold.server.fullname" -}}
{{- if .Values.fullnameOverride }}
{{-   .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{-   $name := default "server" .Values.nameOverride }}
{{-   if contains $name .Release.Name }}
{{-     .Release.Name | trunc 63 | trimSuffix "-" }}
{{-   else }}
{{-     printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{-   end }}
{{- end }}
{{- end }}
