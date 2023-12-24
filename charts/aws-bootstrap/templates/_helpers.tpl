{{/*
Labels to apply to the service account, so k8s can find them
*/}}
{{- define "sa.labels" -}}
app.kubernetes.io/name: "{{ .Values.loadBalancerControllerName }}"
app.kubernetes.io/component: "controller"
{{- end }}

{{/*
Labels to apply to the service account, so k8s can find them
*/}}
{{- define "sa.annotations" -}}
{{- if not .Values.LbControllerRoleArn -}}
{{-   fail "LbControllerRoleArn is not set" }}
{{- end -}}
eks.amazonaws.com/role-arn: {{ .Values.LbControllerRoleArn }}
eks.amazonaws.com/sts-regional-endpoints: "true"
{{- end }}
