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
{{ include "datafold.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}


{{/*
Selector labels
*/}}
{{- define "datafold.selectorLabels" -}}
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
{{- if .Values.storage.storageClass -}}
{{-   if (ne .Values.storage.storageClass "") -}}
{{-     printf "storageClassName: %s" .Values.storage.storageClass -}}
{{-   end -}}
{{- else if .Values.global.storageClass -}}
{{-   if (ne .Values.global.storageClass "") -}}
{{-     printf "storageClassName: %s" .Values.global.storageClass -}}
{{-   end -}}
{{- else if .Values.global.cloudProvider -}}
{{-   if (eq .Values.global.cloudProvider "aws") -}}
{{-     printf "storageClassName: \"sc-datafold-aws\"" -}}
{{-   else if (eq .Values.global.cloudProvider "gcp") -}}
{{-     printf "storageClassName: \"sc-datafold-aws\"" -}}
{{-   else if (eq .Values.global.cloudProvider "azure") -}}
{{-   else -}}
{{      fail .Values.global.cloudProvider " is not a supported cloud provider" }}
{{-   end -}}
{{- else -}}
{{      fail "global.cloudProvider must be set if storageClass is not set." }}
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
The deployment tag to use
*/}}
{{- define "datafold.deployment.name" -}}
{{- if .Values.global.deployment -}}
{{-   if (ne .Values.global.deployment "") -}}
{{-     printf "deployment:%s" .Values.global.deployment -}}
{{-   else -}}
{{      fail "global.deployment name must be set." }}
{{-   end -}}
{{- else -}}
{{    fail "global.deployment name must be set." }}
{{- end -}}
{{- end -}}

{{/*
The deployment tag to use
*/}}
{{- define "datadog.deployment.tag" -}}
{{- if .Values.global.datadog.install -}}
{{-   if .Values.global.deployment -}}
{{-     if (ne .Values.global.deployment "") -}}
{{-       printf "deployment:%s" .Values.global.deployment -}}
{{-     else -}}
{{        fail "datadog deployment tag must be set" }}
{{-     end -}}
{{-   else -}}
{{      fail "datadog deployment tag must be set" }}
{{-   end -}}
{{- end -}}
{{- end -}}
