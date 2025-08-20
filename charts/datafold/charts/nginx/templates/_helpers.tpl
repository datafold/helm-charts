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
{{-   if (eq .Values.global.cloudProvider "aws") -}}
NodePort
{{-   else if (eq .Values.global.cloudProvider "gcp") -}}
{{-     if (eq .Values.ingress.deploy true) -}}
ClusterIP
{{-     else -}}
ClusterIP
{{-     end -}}
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
{{- if .Values.global.nginx.gcpNegName -}}
annotations:
  cloud.google.com/neg: '{"exposed_ports": {"{{ .Values.global.nginx.port }}":{"name": "{{ .Values.global.nginx.gcpNegName }}"}}}'
{{- end }}
{{- if (eq .Values.ingress.deploy true) -}}
annotations:
    cloud.google.com/neg: '{"ingress": true}'
    cloud.google.com/backend-config: '{"default": "{{ include "nginx.fullname" . }}"}'
{{- end }}
{{- end }}
{{- end }}

{{/*
Ingress annotations
Important Google:
* Google does not support FrontendConfig for ILB
* You cannot use Managed Certificates with ILB, you have to provide them in secrets
*/}}
{{- define "nginx.ingress.annotations" -}}
{{- if (eq .Values.global.cloudProvider "azure") -}}
annotations:
  appgw.ingress.kubernetes.io/override-frontend-port: "443"
  appgw.ingress.kubernetes.io/appgw-ssl-certificate: {{ .Values.ingress.sslCertificate }}
{{- end }}
{{- if (eq .Values.global.cloudProvider "aws") -}}
annotations:
  kubernetes.io/ingress.class: alb
  alb.ingress.kubernetes.io/scheme: internal
  alb.ingress.kubernetes.io/target-type: instance
  alb.ingress.kubernetes.io/backend-protocol: HTTP
  alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}, {"HTTPS":443}]'
  alb.ingress.kubernetes.io/ssl-redirect: '443'
  {{- if .Values.ingress.sslCertificate }}
  alb.ingress.kubernetes.io/certificate-arn: {{ .Values.ingress.sslCertificate }}
  {{- end }}
  alb.ingress.kubernetes.io/healthcheck-protocol: HTTP
  alb.ingress.kubernetes.io/healthcheck-port: traffic-port
  alb.ingress.kubernetes.io/healthcheck-path: {{ .Values.ingress.healthz }}
  alb.ingress.kubernetes.io/healthcheck-interval-seconds: '15'
  alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '5'
  alb.ingress.kubernetes.io/success-codes: '200'
  alb.ingress.kubernetes.io/healthy-threshold-count: '2'
  alb.ingress.kubernetes.io/unhealthy-threshold-count: '2'
  alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=300
  {{- if .Values.ingress.secgroups }}
  alb.ingress.kubernetes.io/security-groups: {{ .Values.ingress.secgroups }}
  {{- end }}
  alb.ingress.kubernetes.io/ssl-policy: "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
  {{- if .Values.ingress.subnets }}
  alb.ingress.kubernetes.io/subnets: {{ .Values.ingress.subnets }}
  {{- end }}
  alb.ingress.kubernetes.io/tags: Application=datafold
{{- end }}
{{- if (eq .Values.global.cloudProvider "gcp") -}}
{{- if (eq .Values.ingress.deploy true) -}}
annotations:
  {{- if (eq .Values.ingress.internal true) }}
  kubernetes.io/ingress.class: gce-internal
  {{- else }}
  kubernetes.io/ingress.class: gce
  networking.gke.io/v1beta1.FrontendConfig: {{ include "nginx.fullname" . }}
  {{- end }}
  {{- if (eq .Values.ingress.certificateMethod "managed") }}
  networking.gke.io/managed-certificates: {{ include "nginx.fullname" . }}
  {{- end }}
  {{- if .Values.ingress.staticIpName  }}
  kubernetes.io/ingress.global-static-ip-name: {{ .Values.ingress.staticIpName }}
  {{- end }}
  {{- if (eq .Values.ingress.certificateMethod "preshared") }}
  {{- if .Values.ingress.presharedCertificate }}
  ingress.gcp.kubernetes.io/pre-shared-cert: {{ .Values.ingress.presharedCertificate }}
  {{- end }}
  {{- end }}
  kubernetes.io/ingress.allow-http: "false"
{{- end }}
{{- end }}
{{- end }}

{{/*
Ingress Class Name
*/}}
{{- define "nginx.ingress.class" -}}
{{- if (eq .Values.global.cloudProvider "azure") -}}
ingressClassName: azure-application-gateway
{{- end }}
{{- if (eq .Values.global.cloudProvider "aws") -}}
ingressClassName: alb
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
