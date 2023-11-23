{{/*
Expand the name of the chart.
*/}}
{{- define "datafold.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "datafold.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "datafold.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "datafold.labels" -}}
helm.sh/chart: {{ include "datafold.chart" . }}
{{ include "datafold.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "datafold.selectorLabels" -}}
app.kubernetes.io/name: {{ include "datafold.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "datafold.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "datafold.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Template to derive storage class to use
*/}}
{{- define "datafold.storageClass" -}}
{{- if .Values.global.hostPath -}}
{{-     printf "storageClassName: manual" -}}
{{- else if .Values.storage.storageClass -}}
{{-   if (ne .Values.storage.storageClass "") -}}
{{-     printf "storageClassName: %s" .Values.storageClass -}}
{{-   end -}}
{{- else if .Values.global.storageClass -}}
{{-   if (ne .Values.global.storageClass "") -}}
{{-     printf "storageClassName: %s" .Values.global.storageClass -}}
{{-   end -}}
{{- end -}}
{{- end -}}

{{/*
Name of the datafold secrets location
*/}}
{{- define "datafold.secrets" -}}
{{- printf "%s-secrets" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{/*
Name of the datafold configmap location
*/}}
{{- define "datafold.configmap" -}}
{{- printf "%s-config" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{/*
Check that hostpath is set
*/}}
{{- define "datafold.hostpath.check" -}}
{{- if not .Values.global.hostPath -}}
{{ fail "This version must use global.hostPath setting" }}
{{- end -}}
{{- end -}}

