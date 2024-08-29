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
Setting the service type for the service
*/}}
{{- define "nginx.serviceType" -}}
{{- if .Values.service.typeOverride }}
{{- .Values.service.typeOverride }}
{{- else }}
{{-   if (eq .Values.global.cloudProvider "aws") }}
NodePort
{{-   else if (eq .Values.global.cloudProvider "gcp") -}}
ClusterIP
{{-   else if (eq .Values.global.cloudProvider "azure") -}}
ClusterIP
{{-   end }}
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
{{      fail "Not relevant for GCP" }}
{{-   else if (eq .Values.global.cloudProvider "azure") -}}
{{      fail "Not relevant for Azure" }}
{{-   end }}
{{- end }}

{{/*
Setting the service type for the service
*/}}
{{- define "nginx.load_balancer_ips" -}}
{{- range $idx, $lb_ip := .Values.service.loadBalancerIps }}
set_real_ip_from {{ $lb_ip }}/32;
{{- end }}
{{- end }}

{{/*
Service annotations
*/}}
{{- define "nginx.loadbalancer.annotations" -}}
{{/*
NEG annotations for Google Cloud
*/}}
{{- if (eq .Values.global.cloudProvider "gcp") -}}
annotations:
  cloud.google.com/neg: '{"exposed_ports": {"{{ .Values.global.nginx.port }}":{"name": "{{ .Values.global.nginx.gcpNegName }}"}}}'
{{- end }}
{{- end }}

{{/*
Ingress annotations
*/}}
{{- define "nginx.ingress.annotations" -}}
{{- if (eq .Values.global.cloudProvider "azure") -}}
annotations:
  appgw.ingress.kubernetes.io/override-frontend-port: "443"
  appgw.ingress.kubernetes.io/appgw-ssl-certificate: {{ .Values.ingress.sslCertificate }}
{{- end }}
{{- end }}

{{/*
Ingress Class Name
*/}}
{{- define "nginx.ingress.class" -}}
{{- if (eq .Values.global.cloudProvider "azure") -}}
ingressClassName: azure-application-gateway
{{- end }}
{{- end }}


{{/*
NEG annotations for Google Cloud (in the service)
*/}}
{{- define "nginx.nodeport" -}}
{{- if (eq .Values.global.cloudProvider "aws") -}}
nodePort: {{ .Values.service.nodePort }}
{{- end }}
{{- end }}
