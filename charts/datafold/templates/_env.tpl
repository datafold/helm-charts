{{- define "datafold.env" -}}
- name: CH_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "datafold.secrets" . }}
      key: DATAFOLD_CLICKHOUSE_PASSWORD
- name: CH_USER
  valueFrom:
    secretKeyRef:
      name: {{ include "datafold.secrets" . }}
      key: DATAFOLD_CLICKHOUSE_USER
- name: CH_SERVER
  value: "{{ include "datafold.clickhouse.server" . }}"
- name: CH_PORT
  value: "{{ include "datafold.clickhouse.port" . }}"
- name: CH_DATABASE
  value: "{{ .Values.global.clickhouse.database }}"
- name: CLICKHOUSE_URL
  value: "clickhouse+native://$(CH_USER):$(CH_PASSWORD)@$(CH_SERVER):$(CH_PORT)/$(CH_DATABASE)"
- name: PG_PASS
  valueFrom:
    secretKeyRef:
      name: {{ include "datafold.secrets" . }}
      key: DATAFOLD_POSTGRES_PASSWORD
- name: PG_USER
  valueFrom:
    secretKeyRef:
      name: {{ include "datafold.secrets" . }}
      key: DATAFOLD_POSTGRES_USER
- name: PG_RO_PASS
  valueFrom:
    secretKeyRef:
      name: {{ include "datafold.secrets" . }}
      key: DATAFOLD_RO_DATABASE_PASSWORD
- name: PG_RO_USER
  valueFrom:
    secretKeyRef:
      name: {{ include "datafold.secrets" . }}
      key: DATAFOLD_RO_DATABASE_USER
- name: PG_DB
  valueFrom:
    secretKeyRef:
      name: {{ include "datafold.secrets" . }}
      key: DATAFOLD_POSTGRES_DB
- name: DATAFOLD_DB_ENCRYPTION_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "datafold.secrets" . }}
      key: DATAFOLD_DB_ENCRYPTION_KEY
- name: PG_SERVER
  value: "{{ include "datafold.postgres.server" . }}"
- name: PG_PORT
  value: "{{ include "datafold.postgres.port" . }}"
- name: DATAFOLD_DATABASE_URL
  value: "postgresql://$(PG_USER):$(PG_PASS)@$(PG_SERVER):$(PG_PORT)/$(PG_DB)"
- name: DATAFOLD_RO_DATABASE_URL
  value: "postgresql://$(PG_RO_USER):$(PG_RO_PASS)@$(PG_SERVER):$(PG_PORT)/$(PG_DB)"
- name: REDIS_SERVER
  value: "{{ include "datafold.redis.server" . }}"
- name: REDIS_PORT
  value: "{{ include "datafold.redis.port" . }}"
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "datafold.secrets" . }}
      key: DATAFOLD_REDIS_PASSWORD
- name: DATAFOLD_REDIS_URL
  value: "redis://:$(REDIS_PASSWORD)@$(REDIS_SERVER):$(REDIS_PORT)/0"
- name: DATAFOLD_MAIL_SERVER
  valueFrom:
    secretKeyRef:
      name: {{ include "datafold.secrets" . }}
      key: DATAFOLD_MAIL_SERVER
- name: DATAFOLD_MAIL_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ include "datafold.secrets" . }}
      key: DATAFOLD_MAIL_USERNAME
- name: DATAFOLD_MAIL_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "datafold.secrets" . }}
      key: DATAFOLD_MAIL_PASSWORD
- name: DATAFOLD_MAIL_DEFAULT_SENDER
  valueFrom:
    secretKeyRef:
      name: {{ include "datafold.secrets" . }}
      key: DATAFOLD_MAIL_DEFAULT_SENDER
- name: DATADOG_HOST_IP
  valueFrom:
    fieldRef:
      fieldPath: status.hostIP
- name: DATAFOLD_DATADOG_AGENT_ADDRESS
  value: "{{ include "datafold.datadog.logs.host" . }}:{{ include "datafold.datadog.logs.port" . }}"
- name: DATAFOLD_DATADOG_METRICS_ADDRESS
  value: "$(DATADOG_HOST_IP):{{ include "datafold.datadog.metrics.port" . }}"
- name: COMPONENT_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.labels['app.kubernetes.io/component']
- name: DATAFOLD_SIGNOZ_SERVICE_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.labels['app.kubernetes.io/component']
- name: DATAFOLD_API_ORG_CREATION_DONOR_TOKENS
  valueFrom:
    secretKeyRef:
      name: {{ include "datafold.secrets" . }}
      key: DATAFOLD_API_ORG_CREATION_DONOR_TOKENS
      optional: true
- name: DATAFOLD_ANTHROPIC_API_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "datafold.secrets" . }}
      key: DATAFOLD_ANTHROPIC_API_KEY
      optional: true
{{- range $custom_secret := .Values.global.customSecrets }}
- name: {{ $custom_secret.name }}
  valueFrom:
    secretKeyRef:
      name: {{ include "datafold.secrets" $ }}
      key: {{ $custom_secret.name }}
{{- end }}
{{- end -}}
