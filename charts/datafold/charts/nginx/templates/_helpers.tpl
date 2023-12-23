{{/*
Expand the name of the chart.
*/}}
{{- define "nginx.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "nginx.fullname" -}}
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
Name of config-map.
*/}}
{{- define "nginx.configMap" -}}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- printf "%s-config-map" $name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "nginx.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "nginx.labels" -}}
helm.sh/chart: {{ include "nginx.chart" . }}
app.kubernetes.io/component: ingress
{{ include "nginx.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{ include "datafold.labels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "nginx.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nginx.name" . }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "nginx.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "nginx.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Determine the ingress class to use
*/}}
{{- define "nginx.ingressClassName" -}}
{{- if .Values.ingress.ingressClassOverride }}
{{- .Values.ingress.ingressClassOverride }}
{{- else }}
{{-   if (eq .Values.global.cloudProvider "aws") -}}
{{-   else if (eq .Values.global.cloudProvider "gcp") -}}
{{      fail "GCP is not supported yet" }}
{{-   else if (eq .Values.global.cloudProvider "azure") -}}
{{      fail "Azure is not supported yet" }}
{{-   end }}
{{- end }}
{{- end }}

{{/*
Setting the service type for the service
*/}}
{{- define "nginx.serviceType" -}}
{{- if .Values.service.typeOverride }}
{{- .Values.service.typeOverride }}
{{- else }}
{{-   if (eq .Values.global.cloudProvider "aws") -}}
NodePort
{{-   else if (eq .Values.global.cloudProvider "gcp") -}}
{{      fail "GCP is not supported yet" }}
{{-   else if (eq .Values.global.cloudProvider "azure") -}}
{{      fail "Azure is not supported yet" }}
{{-   end }}
{{- end }}
{{- end }}

{{/*
Create the name of the lb controller service account to use
*/}}
{{- define "nginx.lbController.svcAccountName" -}}
{{- if .Values.global.cloudProvider -}}
{{-   if (eq .Values.global.cloudProvider "aws") -}}
aws-load-balancer-controller
{{-   else if (eq .Values.global.cloudProvider "gcp") -}}
{{      fail "GCP is not supported yet" }}
{{-   else if (eq .Values.global.cloudProvider "azure") -}}
{{      fail "Azure is not supported yet" }}
{{-   end }}
{{- end }}
{{- end }}

{{/*
Labels to apply to the service account, so k8s can find them
*/}}
{{- define "nginx.lbController.labels" -}}
{{- if .Values.global.cloudProvider -}}
{{-   if (eq .Values.global.cloudProvider "aws") -}}
app.kubernetes.io/name: "aws-load-balancer-controller"
app.kubernetes.io/component: "controller"
{{-   else if (eq .Values.global.cloudProvider "gcp") -}}
{{      fail "GCP is not supported yet" }}
{{-   else if (eq .Values.global.cloudProvider "azure") -}}
{{      fail "Azure is not supported yet" }}
{{-   end -}}
{{- end }}
{{- end }}

{{/*
Labels to apply to the service account, so k8s can find them
*/}}
{{- define "nginx.lbController.annotations" -}}
{{- if .Values.global.cloudProvider -}}
{{-   if (eq .Values.global.cloudProvider "aws") -}}
{{-     if not .Values.global.awsLbCtrlArn -}}
{{-       fail "global.awsLbCtrlArn is not set" }}
{{-     end -}}
eks.amazonaws.com/role-arn: {{ .Values.global.awsLbCtrlArn }}
eks.amazonaws.com/sts-regional-endpoints: "true"
{{-   else if (eq .Values.global.cloudProvider "gcp") -}}
{{      fail "GCP is not supported yet" }}
{{-   else if (eq .Values.global.cloudProvider "azure") -}}
{{      fail "Azure is not supported yet" }}
{{-   end -}}
{{- end }}
{{- end }}

{{/*
Setting the service type for the service
*/}}
{{- define "nginx.aws.targetGroupArn" -}}
{{-   if (eq .Values.global.cloudProvider "aws") -}}
{{-     if not .Values.global.awsTargetGroupArn -}}
{{-       fail "global.awsTargetGroupArn is not set" }}
{{-     end -}}
{{ .Values.global.awsTargetGroupArn }}
{{-   else if (eq .Values.global.cloudProvider "gcp") -}}
{{      fail "GCP is not supported yet" }}
{{-   else if (eq .Values.global.cloudProvider "azure") -}}
{{      fail "Azure is not supported yet" }}
{{-   end }}
{{- end }}
